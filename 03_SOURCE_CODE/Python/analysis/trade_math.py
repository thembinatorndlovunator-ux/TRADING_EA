"""R-multiple and MFE/MAE math shared by several analysis scripts.

``compute_r_multiple`` is a direct Python port of
``ExitManager.mqh``'s ``EM_ComputeR`` (TASK-030) -- kept algebraically
identical deliberately, so a Python-side R figure and an MQL5-side one
computed from the same entry/stop/price are guaranteed to agree; this
module does not re-derive the formula independently.
"""

from __future__ import annotations

from dataclasses import dataclass

import pandas as pd


def compute_r_multiple(is_long: bool, entry_price: float, initial_stop_price: float, price: float) -> float:
    """Mirrors ExitManager.mqh's EM_ComputeR exactly: R = favor_distance /
    risk_distance. Returns 0.0 (never divides by zero) if the initial risk
    distance is non-positive, matching the MQL5 fail-safe behavior."""

    risk_distance = (entry_price - initial_stop_price) if is_long else (initial_stop_price - entry_price)
    if risk_distance <= 0.0:
        return 0.0

    favor_distance = (price - entry_price) if is_long else (entry_price - price)
    return favor_distance / risk_distance


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


def compute_mfe_mae(
    trade_id: str,
    is_long: bool,
    entry_price: float,
    stop_price: float,
    entry_time: pd.Timestamp,
    exit_time: pd.Timestamp,
    bars: pd.DataFrame,
) -> MfeMaeResult:
    """Computes MFE/MAE for one trade from a bars DataFrame with
    'timestamp', 'high', 'low' columns (any symbol filtering is the
    caller's responsibility -- this function does not know about
    symbols). The window is inclusive of both entry_time and exit_time.

    **Bar-timestamp convention, declared explicitly (Codex review
    finding, 2026-07-22): 'timestamp' is the bar's OPEN time** (the
    standard MT5 convention). Without this declared and enforced,
    entry_time/exit_time could fall ANYWHERE inside a bar's true
    [open, close) span -- the entry bar's full high/low could include
    price action from before the trade actually opened, and the exit
    bar's could include price action from after it actually closed
    (look-ahead/measurement contamination, not a mere approximation).

    **Alignment is now REQUIRED, not silently tolerated:** entry_time and
    exit_time must each exactly match a bar timestamp present in
    'bars' -- this bounds the residual approximation to "the single
    entry/exit bar's full range may include some price action from
    outside the trade's true open instant" (a known, documented
    limitation that genuinely requires tick/sub-bar data to eliminate
    entirely) rather than allowing UNBOUNDED misalignment across
    multiple bars. Raises BarAlignmentError if either timestamp is not
    an exact bar timestamp.

    Raises NoBarsInWindowError if no bar falls within the window -- a
    trade with a computable MFE/MAE of exactly 0.0 is different from a
    trade with no data at all, and the two must never be conflated.
    """

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

    window = bars[(bars["timestamp"] >= entry_time) & (bars["timestamp"] <= exit_time)]
    if window.empty:
        raise NoBarsInWindowError(
            f"trade_id={trade_id}: no bars found between {entry_time} and {exit_time}"
        )

    if is_long:
        mfe_price = max(0.0, float(window["high"].max()) - entry_price)
        mae_price = max(0.0, entry_price - float(window["low"].min()))
    else:
        mfe_price = max(0.0, entry_price - float(window["low"].min()))
        mae_price = max(0.0, float(window["high"].max()) - entry_price)

    mfe_r = compute_r_multiple(is_long, entry_price, stop_price, entry_price + mfe_price if is_long else entry_price - mfe_price)
    mae_r = compute_r_multiple(is_long, entry_price, stop_price, entry_price - mae_price if is_long else entry_price + mae_price)

    return MfeMaeResult(
        trade_id=trade_id,
        mfe_price=mfe_price,
        mae_price=mae_price,
        mfe_r=mfe_r,
        mae_r=mae_r,
        n_bars=len(window),
    )
