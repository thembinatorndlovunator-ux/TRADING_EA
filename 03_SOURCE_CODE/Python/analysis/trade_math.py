"""R-multiple and MFE/MAE math shared by several analysis scripts.

``compute_r_multiple`` is a direct Python port of
``ExitManager.mqh``'s ``EM_ComputeR`` (TASK-030) -- kept algebraically
identical deliberately, so a Python-side R figure and an MQL5-side one
computed from the same entry/stop/price are guaranteed to agree; this
module does not re-derive the formula independently.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import pandas as pd


def compute_r_multiple(
    is_long: bool, entry_price: float, initial_stop_price: float, price: float
) -> float:
    """Mirrors ExitManager.mqh's EM_ComputeR exactly: R = favor_distance /
    risk_distance. Returns 0.0 (never divides by zero) if the initial risk
    distance is non-positive, matching the MQL5 fail-safe behavior.

    Raises ValueError if the result overflows to a non-finite value --
    **added, 2026-07-22 Codex review finding (sixth round): a tiny-but-
    positive risk_distance combined with a large-but-finite
    favor_distance previously overflowed this division silently, with no
    check anywhere in this shared primitive. Reproduced counterexamples
    traced back to this exact gap: calculate_mfe_mae.py's mfe_r == inf
    with no row error from finite bar prices, and analyse_giveback.py's
    actual_final_r == inf / v637_r_diff == nan (inf - inf) with no row
    error from a finite exit_price. This is the one shared function every
    affected caller already routes through (calculate_mfe_mae.py,
    analyse_giveback.py, compare_releases.py, walk_forward.py), so fixing
    it here closes the gap for all of them at once -- every caller
    already either catches ValueError as a per-row error or lets it
    propagate to its own CLI's existing ValueError handler, so this
    raise does not change either pipeline's error-reporting shape.**
    """

    risk_distance = (
        (entry_price - initial_stop_price) if is_long else (initial_stop_price - entry_price)
    )
    if risk_distance <= 0.0:
        return 0.0

    favor_distance = (price - entry_price) if is_long else (entry_price - price)
    r_multiple = favor_distance / risk_distance
    if not math.isfinite(r_multiple):
        raise ValueError(
            f"compute_r_multiple: result overflowed to a non-finite value ({r_multiple!r}) from "
            f"favor_distance={favor_distance!r}, risk_distance={risk_distance!r}"
        )
    return r_multiple


@dataclass(frozen=True)
class MfeMaeResult:
    trade_id: str
    mfe_price: float  # max favorable excursion, in price distance (>= 0)
    mae_price: float  # max adverse excursion, in price distance (>= 0)
    mfe_r: float
    mae_r: float
    n_bars: int


class NoBarsInWindowError(ValueError):
    """Raised when a trade's [entry_time, exit_time] window has zero bars
    to compute MFE/MAE from -- never silently reported as 0.0 excursion,
    since that would be indistinguishable from a genuinely flat trade.

    **Note:** since entry_time/exit_time alignment to an actual bar
    timestamp is now REQUIRED (see compute_mfe_mae's own docstring,
    Codex review finding 2026-07-22), this window can structurally never
    be empty once alignment passes -- BarAlignmentError is what a caller
    actually encounters for a misaligned or no-data case. This class is
    kept as defensive dead code rather than removed, in case a future
    change relaxes the alignment requirement."""


class BarAlignmentError(ValueError):
    """Raised when entry_time or exit_time does not exactly match a bar
    timestamp present in the supplied bars -- see compute_mfe_mae's own
    docstring for why this matters."""


class IncompleteBarCoverageError(ValueError):
    """Raised when the bars actually present in a trade's
    [entry_time, exit_time) window do not form a COMPLETE, gap-free
    sequence at the caller-declared cadence -- endpoint alignment alone
    (entry_time/exit_time each matching SOME bar) does not guarantee
    every bar IN BETWEEN is also present.

    **Added, 2026-07-22 Codex review finding (fifth round): a trade from
    00:00 to 03:00 with bars only at 00:00 and 03:00 (the exit bar itself
    excluded by the half-open window) previously completed successfully
    and reported ONE measured bar, silently ignoring the missing 01:00
    and 02:00 exposure -- endpoint alignment was enforced, but expected
    cadence/timeframe and gaps were not.** With an expected 60-minute
    cadence declared, this trade's window should contain bars at 00:00,
    01:00, and 02:00 (3 bars, matching a 3-hour half-open window) -- only
    1 was present, so the guard/exposure data used to compute MFE/MAE is
    genuinely incomplete, not a legitimately sparse market.
    """


class ZeroDurationTradeUnmeasurableError(ValueError):
    """Raised when entry_time == exit_time (a trade with zero recorded
    duration). Under this module's own bar-OPEN convention, equal
    entry/exit timestamps describe a trade open for ZERO time at the bar
    open instant -- MFE/MAE cannot be measured from that single bar's
    full high/low range, since that range spans the bar's ENTIRE
    [timestamp, next_bar_open) period, almost all of which occurs AFTER
    the trade already exited. **Fixed, 2026-07-22 Codex review finding
    (fourth round): a previous same-bar exception used the single aligned
    bar's full range for exactly this case -- a probe with one bar
    (high=999, low=0, entry=100, stop=98) returned mfe_r=449.5 and a
    large-magnitude mae_r, almost entirely from price action after the
    recorded exit. This is genuinely unmeasurable at bar resolution
    (would require tick/sub-bar data), so it is now rejected outright
    rather than silently approximated.**"""


def assert_complete_bar_coverage(
    window_timestamps: pd.Series,
    window_start: pd.Timestamp,
    window_end: pd.Timestamp,
    expected_cadence_minutes: float,
    trade_id: str,
) -> None:
    """Raises IncompleteBarCoverageError unless 'window_timestamps' (the
    bar timestamps actually found within a trade's [window_start,
    window_end) half-open window) form a COMPLETE, gap-free sequence at
    exactly 'expected_cadence_minutes' -- i.e. exactly
    ``(window_end - window_start) / cadence`` bars, each exactly one
    cadence apart from the next. Endpoint alignment alone (the window's
    two boundaries each matching SOME bar) does not guarantee every bar
    IN BETWEEN is also present.

    **Added, 2026-07-22 Codex review finding (fifth round): shared by
    ``compute_mfe_mae`` and ``analyse_giveback.py``'s own R-path
    construction -- both previously accepted a sparse bar subset as
    complete evidence merely because it was non-empty and its endpoints
    were aligned.**

    Raises ValueError if 'expected_cadence_minutes' is not finite and > 0,
    or if the window duration is not an exact multiple of it.
    """

    if not math.isfinite(expected_cadence_minutes) or expected_cadence_minutes <= 0:
        raise ValueError(
            f"trade_id={trade_id}: expected_cadence_minutes must be a finite number > 0, "
            f"got {expected_cadence_minutes}"
        )
    cadence = pd.Timedelta(minutes=expected_cadence_minutes)
    expected_bar_count = (window_end - window_start) / cadence
    if expected_bar_count != round(expected_bar_count):
        raise IncompleteBarCoverageError(
            f"trade_id={trade_id}: window duration ({window_end - window_start}) is not an "
            f"exact multiple of the declared {expected_cadence_minutes}-minute cadence -- "
            "cannot verify complete bar coverage"
        )
    expected_bar_count = round(expected_bar_count)
    if len(window_timestamps) != expected_bar_count:
        raise IncompleteBarCoverageError(
            f"trade_id={trade_id}: window [{window_start}, {window_end}) at "
            f"{expected_cadence_minutes}-minute cadence should contain {expected_bar_count} "
            f"bar(s), found {len(window_timestamps)} -- incomplete bar coverage (a gap in the "
            "bars input), not a legitimately sparse market"
        )
    sorted_timestamps = sorted(window_timestamps)
    for i in range(len(sorted_timestamps) - 1):
        gap = sorted_timestamps[i + 1] - sorted_timestamps[i]
        if gap != cadence:
            raise IncompleteBarCoverageError(
                f"trade_id={trade_id}: bars at {sorted_timestamps[i]} and "
                f"{sorted_timestamps[i + 1]} are {gap} apart, not the declared "
                f"{expected_cadence_minutes}-minute cadence -- a gap or duplicate in the bars "
                "input"
            )


def compute_mfe_mae(
    trade_id: str,
    is_long: bool,
    entry_price: float,
    stop_price: float,
    entry_time: pd.Timestamp,
    exit_time: pd.Timestamp,
    bars: pd.DataFrame,
    *,
    # **Added, 2026-07-22 Codex review finding (fifth round): see
    # IncompleteBarCoverageError's own docstring for the exact
    # counterexample this closes. Required (not optional) so a caller
    # cannot silently skip declaring what cadence its own bars.csv export
    # is supposed to be at.**
    expected_cadence_minutes: float,
) -> MfeMaeResult:
    """Computes MFE/MAE for one trade from a bars DataFrame with
    'timestamp', 'high', 'low' columns (any symbol filtering is the
    caller's responsibility -- this function does not know about
    symbols).

    'expected_cadence_minutes' is the caller-declared bar interval (e.g.
    1.0 for M1 bars) -- the window's actual bars must form a COMPLETE,
    gap-free sequence at exactly this cadence (see
    IncompleteBarCoverageError's own docstring), not merely have their
    two ENDPOINTS aligned to some bar.

    **Bar-timestamp convention, declared explicitly: 'timestamp' is the
    bar's OPEN time** (the standard MT5 convention).

    **Fixed, 2026-07-22 Codex review finding (third round): the window
    was previously INCLUSIVE of exit_time** (``timestamp <= exit_time``)
    -- but a bar whose OPEN time equals exit_time spans
    ``[exit_time, next_bar_open)``, a period that occurs ENTIRELY AFTER
    the trade has already exited. A direct two-bar probe (entry 00:00,
    exit 01:00, an extreme 01:00 bar) previously returned mfe_r=449.5
    almost entirely from POST-EXIT price movement -- real look-ahead
    contamination, not a documentation-only caveat. Under the declared
    bar-open convention the correct window is the HALF-OPEN interval
    ``[entry_time, exit_time)`` -- the exit bar itself is excluded
    (its price action happens after the exit instant), while the entry
    bar IS included (its price action begins at the entry instant). The
    one exception previously used was a same-bar trade
    (``entry_time == exit_time``), which used the single aligned bar
    instead. **Fixed, 2026-07-22 Codex review finding (fourth round):
    that same-bar case is a ZERO-DURATION trade at the bar-open instant
    -- that bar's FULL high/low range spans its entire
    [timestamp, next_bar_open) period, almost all of which occurs AFTER
    the trade already exited (a probe with one extreme bar returned
    mfe_r=449.5 almost entirely from post-exit price action). This is
    genuinely unmeasurable at bar resolution (it would require tick/
    sub-bar data), so it now raises ZeroDurationTradeUnmeasurableError
    instead of approximating it from that bar's range.**

    **Alignment is still REQUIRED, not silently tolerated:** entry_time
    and exit_time must each exactly match a bar timestamp present in
    'bars' -- this bounds the residual approximation (the entry bar's
    full range may include price action from slightly before the exact
    entry instant, a known limitation that genuinely requires tick/
    sub-bar data to eliminate entirely) rather than allowing UNBOUNDED
    misalignment across multiple bars. Raises BarAlignmentError if
    either timestamp is not an exact bar timestamp.

    Raises ZeroDurationTradeUnmeasurableError if entry_time == exit_time
    (see above). Raises NoBarsInWindowError if no bar falls within the
    window -- a trade with a computable MFE/MAE of exactly 0.0 is
    different from a trade with no data at all, and the two must never
    be conflated. Raises ValueError if 'expected_cadence_minutes' is not
    finite and > 0. Raises IncompleteBarCoverageError if the window's
    bars do not form a complete, gap-free sequence at that cadence.
    """

    if not math.isfinite(expected_cadence_minutes) or expected_cadence_minutes <= 0:
        raise ValueError(
            f"trade_id={trade_id}: expected_cadence_minutes must be a finite number > 0, "
            f"got {expected_cadence_minutes}"
        )
    if entry_time > exit_time:
        raise ValueError(f"entry_time ({entry_time}) must not be after exit_time ({exit_time})")

    bar_timestamps = set(bars["timestamp"])
    if entry_time not in bar_timestamps:
        raise BarAlignmentError(
            f"trade_id={trade_id}: entry_time ({entry_time}) does not match any bar timestamp "
            "(bar timestamps are bar-OPEN times -- see compute_mfe_mae's own docstring)"
        )
    if exit_time not in bar_timestamps:
        raise BarAlignmentError(
            f"trade_id={trade_id}: exit_time ({exit_time}) does not match any bar timestamp "
            "(bar timestamps are bar-OPEN times -- see compute_mfe_mae's own docstring)"
        )

    if entry_time == exit_time:
        raise ZeroDurationTradeUnmeasurableError(
            f"trade_id={trade_id}: entry_time == exit_time ({entry_time}) -- MFE/MAE for a "
            "zero-duration trade is unmeasurable at bar resolution (see "
            "ZeroDurationTradeUnmeasurableError's own docstring); requires tick/sub-bar data"
        )

    window = bars[(bars["timestamp"] >= entry_time) & (bars["timestamp"] < exit_time)]
    if window.empty:
        raise NoBarsInWindowError(
            f"trade_id={trade_id}: no bars found between {entry_time} and {exit_time}"
        )

    # **Added, 2026-07-22 Codex review finding (fifth round): endpoint
    # alignment (checked above) does not guarantee every bar IN BETWEEN
    # is also present -- see IncompleteBarCoverageError's own docstring
    # for the exact reproduced counterexample.
    assert_complete_bar_coverage(
        window["timestamp"], entry_time, exit_time, expected_cadence_minutes, trade_id
    )

    if is_long:
        mfe_price = max(0.0, float(window["high"].max()) - entry_price)
        mae_price = max(0.0, entry_price - float(window["low"].min()))
    else:
        mfe_price = max(0.0, entry_price - float(window["low"].min()))
        mae_price = max(0.0, float(window["high"].max()) - entry_price)

    mfe_r = compute_r_multiple(
        is_long,
        entry_price,
        stop_price,
        entry_price + mfe_price if is_long else entry_price - mfe_price,
    )
    mae_r = compute_r_multiple(
        is_long,
        entry_price,
        stop_price,
        entry_price - mae_price if is_long else entry_price + mae_price,
    )

    return MfeMaeResult(
        trade_id=trade_id,
        mfe_price=mfe_price,
        mae_price=mae_price,
        mfe_r=mfe_r,
        mae_r=mae_r,
        n_bars=len(window),
    )
