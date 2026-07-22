"""Performance-metric primitives shared by every analysis pipeline.

Per the reproducibility contract: "Statistical claims report sample size
and uncertainty. Tiny samples cannot drive automatic live parameter
changes." Every function here raises ``InsufficientSampleError`` on an
empty input rather than returning a silently-meaningless 0.0/NaN -- a
caller must handle the empty case explicitly, never plot or report a
number that was never actually computed.

**Corrected, 2026-07-22 Codex review finding (third round):** this
docstring previously claimed every function ALSO returns uncertainty
alongside sample size -- that overstates what is actually implemented.
``win_rate``/``expectancy``/``bootstrap_confidence_interval`` do (Wilson
CI, bootstrap CI, percentile CI respectively). ``profit_factor`` and
``compute_max_drawdown`` report ONLY a point estimate -- no inferential
interval exists for either statistic here -- a caller needing drawdown
uncertainty should use ``monte_carlo.py``'s resampled drawdown
distribution instead, which does carry percentile scenario bounds.

**Corrected, 2026-07-22 Codex review finding (fourth round):** this
docstring (and ``ProfitFactorResult`` itself) previously implied ``n``
was recoverable from ``n_wins``/``n_losses`` alone -- false, since
break-even (exactly-zero P/L) observations are counted in neither and
silently vanish from the total. ``ProfitFactorResult.n`` now reports the
TRUE total sample size (wins + losses + break-even), independent of
``n_wins + n_losses``.
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
    n: int  # **Added, 2026-07-22 Codex review finding (fourth round):**
    # the TRUE total sample size (wins + losses + break-even) -- NOT
    # recoverable from n_wins + n_losses alone, since an exactly-zero
    # P/L observation is counted in neither and previously vanished from
    # the result entirely.


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


def wilson_confidence_interval(
    successes: int, n: int, confidence: float = 0.95
) -> tuple[float, float]:
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
        diff=diff,
        ci_lower=lower,
        ci_upper=upper,
        likely_significant=(lower > 0.0 or upper < 0.0),
        n_a=n_a,
        n_b=n_b,
        confidence=confidence,
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
    uncertainty-free, expectancy). Raises ValueError if any value is
    non-finite (NaN/inf) -- **fixed, 2026-07-22 Codex review finding
    (third round): the n==1 branch previously ran BEFORE any finiteness
    check, so ``expectancy([NaN])`` silently returned a NaN expectancy
    instead of a visible error.**
    """

    n = len(pnl)
    if n == 0:
        raise InsufficientSampleError("expectancy: empty pnl sequence")
    if not all(math.isfinite(x) for x in pnl):
        raise ValueError("expectancy: pnl contains a non-finite (NaN/inf) value")

    mean = sum(pnl) / n
    if n == 1:
        return ExpectancyResult(
            expectancy=mean,
            n=n,
            std_dev=None,
            ci_lower=None,
            ci_upper=None,
            confidence=None,
            n_resamples=None,
            seed=None,
        )

    # **Fixed, 2026-07-22 Codex review finding (fifth round):** Python's
    # float ``**`` raises ``OverflowError`` outright (not a silent inf)
    # when the squared magnitude exceeds float range -- a probe with
    # ``[1e308, -1e308]`` raised an UNCAUGHT OverflowError here, before
    # the post-compute finiteness check below ever ran. Caught explicitly
    # and converted to the same visible-failure contract as every other
    # overflow in this module.
    try:
        variance = sum((x - mean) ** 2 for x in pnl) / (n - 1)
    except OverflowError as exc:
        raise ValueError(
            f"expectancy: variance calculation overflowed ({exc}) -- the input pnl values are "
            "finite individually but their squared deviation from the mean is not"
        ) from exc
    std_dev = math.sqrt(variance)
    boot = bootstrap_confidence_interval(
        pnl, statistic="mean", n_resamples=n_resamples, confidence=confidence, seed=seed
    )
    # **Added, 2026-07-22 Codex review finding (fourth round):** every
    # individual 'pnl' value is checked finite above, but SUMS/DIFFERENCES
    # of finite values can still overflow to +/-inf, and inf arithmetic
    # downstream produces NaN (e.g. inf - inf) -- independent probes found
    # expectancy([1e308, 1e308], n_resamples=100) returns mean/std_dev=inf
    # and ci_lower/ci_upper=[nan, nan]. A pipeline must fail visibly rather
    # than persist non-finite statistical evidence.
    if not (
        math.isfinite(mean)
        and math.isfinite(std_dev)
        and math.isfinite(boot.ci_lower)
        and math.isfinite(boot.ci_upper)
    ):
        raise ValueError(
            f"expectancy: computed statistic overflowed to a non-finite value "
            f"(mean={mean}, std_dev={std_dev}, ci=[{boot.ci_lower}, {boot.ci_upper}]) -- "
            "the input pnl values are finite individually but their sum/variance is not"
        )
    return ExpectancyResult(
        expectancy=mean,
        n=n,
        std_dev=std_dev,
        ci_lower=boot.ci_lower,
        ci_upper=boot.ci_upper,
        confidence=confidence,
        n_resamples=n_resamples,
        seed=seed,
    )


def profit_factor(pnl: Sequence[float]) -> ProfitFactorResult:
    """gross_profit / abs(gross_loss). Raises InsufficientSampleError if
    empty. Raises ValueError if any value is non-finite -- **fixed,
    2026-07-22 Codex review finding (third round):
    ``profit_factor([NaN])`` previously returned an "undefined" (None)
    factor with zero wins/losses, since ``NaN > 0``/``NaN < 0`` are both
    False in Python, silently classifying a NaN as neither a win nor a
    loss instead of raising.** If there are zero losing trades,
    ``profit_factor`` is returned as None (not float('inf')) -- an
    explicitly undefined value a caller must handle, rather than a
    special float that silently poisons any downstream arithmetic or
    gets misread as a real (huge) number."""

    n = len(pnl)
    if n == 0:
        raise InsufficientSampleError("profit_factor: empty pnl sequence")
    if not all(math.isfinite(x) for x in pnl):
        raise ValueError("profit_factor: pnl contains a non-finite (NaN/inf) value")

    gross_profit = sum(x for x in pnl if x > 0)
    gross_loss = sum(x for x in pnl if x < 0)  # negative or zero
    n_wins = sum(1 for x in pnl if x > 0)
    n_losses = sum(1 for x in pnl if x < 0)

    # **Added, 2026-07-22 Codex review finding (fourth round):** each
    # individual value is checked finite above, but SUMMING many finite
    # values can still overflow -- an independent probe with
    # profit_factor([1e308, 1e308, -1]) produced gross_profit=inf and an
    # inf factor. A pipeline must fail visibly rather than persist a
    # non-finite gross_profit/gross_loss/factor.
    if not (math.isfinite(gross_profit) and math.isfinite(gross_loss)):
        raise ValueError(
            f"profit_factor: gross_profit/gross_loss overflowed to a non-finite value "
            f"(gross_profit={gross_profit}, gross_loss={gross_loss}) -- "
            "the input pnl values are finite individually but their sum is not"
        )

    if gross_loss == 0.0:
        pf = None
    else:
        pf = gross_profit / abs(gross_loss)
        if not math.isfinite(pf):
            raise ValueError(
                f"profit_factor: computed factor overflowed to a non-finite value ({pf})"
            )

    return ProfitFactorResult(
        profit_factor=pf,
        gross_profit=gross_profit,
        gross_loss=gross_loss,
        n_wins=n_wins,
        n_losses=n_losses,
        n=n,
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
        raise ValueError(
            f"n_resamples must be >= {MIN_N_RESAMPLES} for a defensible CI, got {n_resamples}"
        )

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

    # **Added, 2026-07-22 Codex review finding (fifth round):** every
    # individual value is checked finite above, but the resampled mean/
    # median can still overflow -- a probe with ``[1e308, -1e308]``
    # returned a NUMPY-SILENT point estimate of ``0.0`` with
    # ``ci=[NaN, NaN]`` rather than a visible failure.
    if not (math.isfinite(point) and math.isfinite(lower) and math.isfinite(upper)):
        raise ValueError(
            f"bootstrap_confidence_interval: computed statistic overflowed to a non-finite "
            f"value (point={point}, ci=[{lower}, {upper}]) -- the input data values are finite "
            "individually but their resampled statistic is not"
        )

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
        raise ValueError(
            "compute_max_drawdown: balance_curve contains a non-finite (NaN/inf) value"
        )
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
        # **Added, 2026-07-22 Codex review finding (fifth round):** every
        # individual value is checked finite above, but 'peak - value' can
        # still overflow to inf when the two are huge and opposite-signed
        # -- a probe with [1e308, -1e308] produced an infinite absolute
        # AND percentage drawdown with no guard at all in this function.
        if not (math.isfinite(dd_abs) and math.isfinite(dd_pct)):
            raise ValueError(
                f"compute_max_drawdown: drawdown overflowed to a non-finite value at index {i} "
                f"(peak={peak!r}, value={value!r}) -- the input values are finite individually "
                "but their difference is not"
            )

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


@dataclass(frozen=True)
class BalancePeakGivebackResult:
    """See ``compute_balance_peak_giveback``'s own docstring for the exact
    arm/trigger formula and, critically, for why this is NOT the master-
    prompt-required account/daily equity-peak-giveback metric. This is
    DESCRIPTIVE (offline analysis of a historical curve), never a live
    control -- matches every other module in this project that ports a
    live guard formula for retrospective simulation only.
    """

    arm_percent: float
    floor_percent: float
    armed: bool  # whether the running peak ever grew >= arm_percent above the curve's start
    n_trigger_events: int
    trigger_indices: list[int]
    max_giveback_pct: float  # 0.0 if never armed
    max_giveback_pct_index: int


def compute_balance_peak_giveback(
    balance_curve: Sequence[float], arm_percent: float = 1.0, floor_percent: float = 0.5
) -> BalancePeakGivebackResult:
    """Simulates ``TASK-002_PHASE2_SPECIFICATION.md``'s giveback-guard
    ARM/TRIGGER formula against a chronologically-ordered CLOSED-TRADE
    BALANCE curve -- reports how many times a peak-relative giveback guard
    would have TRIGGERED, not just the single worst decline
    (``compute_max_drawdown`` reports that instead).

    **Renamed from ``compute_equity_peak_giveback``, and re-scoped
    explicitly (Codex review finding, 2026-07-22, fifth round): this is
    NOT a measurement of either master-prompt-required equity-peak-
    giveback metric.** The spec defines TWO real metrics this function
    does not compute: an "Account equity-peak giveback" (needs a genuine
    intratrade, mark-to-market EQUITY series -- this project has no
    intraday equity ticks yet, only closed-trade balance, see
    ``analyse_baseline.py``'s "Balance, not equity" disclosure) and a
    "Daily equity-peak giveback" (needs a DAILY reset of the running peak
    at a genuine calendar-day boundary -- this function's peak never
    resets, it runs over the WHOLE curve). It is also a different
    quantity from ``analyse_giveback.py``'s own guard simulation (which
    operates per-TRADE on an R-multiple path, not per-BAR on an account
    curve). Closing the real account/daily equity-peak-giveback gap needs
    an account equity-tick export -- an unimplemented TASK-037 input (see
    that task's Files-affected list) -- not a relabeling of this
    function; do not report this result under an "equity" name anywhere.

    The running peak arms the guard once
    ``(peak - start) / start >= arm_percent / 100``; once armed, a trigger
    event fires the first time
    ``(peak - current) / peak >= floor_percent / 100`` after the guard was
    last below that floor (so a single sustained decline counts as ONE
    trigger event, not one per bar -- re-triggering requires the giveback
    to first recover below the floor).

    Raises InsufficientSampleError if empty. Raises ValueError if any
    value is non-finite, if the first value is not strictly positive
    (percent-based, same requirement as ``compute_max_drawdown``), if
    'arm_percent'/'floor_percent' is not finite and > 0, or if the
    computed giveback percentage overflows to a non-finite value (Codex
    review finding, 2026-07-22, fifth round: ``[5e307, 1e308, -1e308]``
    previously produced an infinite ``max_giveback_pct``).
    """

    if not balance_curve:
        raise InsufficientSampleError("compute_balance_peak_giveback: empty balance curve")
    if not all(math.isfinite(v) for v in balance_curve):
        raise ValueError(
            "compute_balance_peak_giveback: balance_curve contains a non-finite (NaN/inf) value"
        )
    if balance_curve[0] <= 0:
        raise ValueError(
            f"compute_balance_peak_giveback: the first value ({balance_curve[0]!r}) must be > 0"
        )
    if not math.isfinite(arm_percent) or arm_percent <= 0:
        raise ValueError(f"arm_percent must be finite and > 0, got {arm_percent}")
    if not math.isfinite(floor_percent) or floor_percent <= 0:
        raise ValueError(f"floor_percent must be finite and > 0, got {floor_percent}")

    start = balance_curve[0]
    peak = start
    armed = False
    currently_triggered = False
    n_trigger_events = 0
    trigger_indices: list[int] = []
    max_giveback_pct = 0.0
    max_giveback_pct_index = 0

    for i, value in enumerate(balance_curve):
        if value > peak:
            peak = value

        if not armed and (peak - start) / start >= arm_percent / 100.0:
            armed = True

        if armed:
            giveback_pct = (peak - value) / peak
            if not math.isfinite(giveback_pct):
                raise ValueError(
                    f"compute_balance_peak_giveback: giveback percentage overflowed to a "
                    f"non-finite value at index {i} (peak={peak!r}, value={value!r})"
                )
            if giveback_pct > max_giveback_pct:
                max_giveback_pct = giveback_pct
                max_giveback_pct_index = i

            if giveback_pct >= floor_percent / 100.0:
                if not currently_triggered:
                    n_trigger_events += 1
                    trigger_indices.append(i)
                    currently_triggered = True
            else:
                currently_triggered = False

    return BalancePeakGivebackResult(
        arm_percent=arm_percent,
        floor_percent=floor_percent,
        armed=armed,
        n_trigger_events=n_trigger_events,
        trigger_indices=trigger_indices,
        max_giveback_pct=max_giveback_pct,
        max_giveback_pct_index=max_giveback_pct_index,
    )
