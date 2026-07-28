"""Python ports of ExitManager.mqh's (TASK-030) giveback-guard predicates,
used ONLY for OFFLINE simulation of "would this guard have triggered a
close, and at what R" against historical bar data -- this module never
controls, and is never wired to, any live trading action. Kept
algebraically identical to the MQL5 source (not re-derived) so a Python
simulation and a future live MQL5 run of the same guard would agree.

Both models are "default off until Phase 8 evidence" in ExitManager.mqh
itself -- this module is part of gathering that evidence offline, not an
argument that either model should be enabled live.
"""

from __future__ import annotations

from typing import Literal, Optional, Sequence


def should_giveback_close_v637(
    current_r: float,
    peak_r: float,
    arm_rr: float,
    giveback_percent: float,
    close_trigger_floor_r: float,
) -> bool:
    """Direct port of ExitManager.mqh's EM_ShouldGivebackCloseV637."""

    effective_arm = max(0.25, arm_rr)
    if peak_r < effective_arm:
        return False

    clamped_percent = max(10.0, min(90.0, giveback_percent))
    trigger_r = peak_r * (1.0 - clamped_percent / 100.0)
    if trigger_r < close_trigger_floor_r:
        trigger_r = close_trigger_floor_r

    return current_r <= trigger_r


def should_giveback_close_v811(
    current_r: float, peak_r: float, arm_r: float, floor_r: float
) -> bool:
    """Direct port of ExitManager.mqh's EM_ShouldGivebackCloseV811."""

    effective_arm = max(0.3, arm_r)
    if peak_r < effective_arm:
        return False

    effective_floor = max(0.0, floor_r)
    return current_r <= effective_floor


GivebackModel = Literal["v637", "v811"]


def simulate_giveback_path(
    r_path: Sequence[float],
    model: GivebackModel,
    *,
    arm_rr: float = 1.25,
    giveback_percent: float = 60.0,
    close_trigger_floor_r: float = 0.05,
    arm_r: float = 0.8,
    floor_r: float = 0.1,
) -> Optional[tuple[int, float]]:
    """Walks 'r_path' (chronological R values, one per bar, from entry to
    exit) and returns (bar_index, r_at_trigger) for the FIRST bar where the
    named giveback model would have closed the trade, or None if it never
    triggers across the whole path. 'peak_r' is tracked from 0.0 (a trade
    starts at 0R by definition) and only ever increases, mirroring
    ExitManager.mqh's caller-tracked 'peak_r' state convention.

    Raises ValueError for an empty path or an unknown model name.
    """

    if not r_path:
        raise ValueError("simulate_giveback_path: r_path must not be empty")
    if model not in ("v637", "v811"):
        raise ValueError(f"unknown giveback model: {model!r}")

    peak_r = 0.0
    for index, current_r in enumerate(r_path):
        if current_r > peak_r:
            peak_r = current_r

        if model == "v637":
            triggered = should_giveback_close_v637(
                current_r, peak_r, arm_rr, giveback_percent, close_trigger_floor_r
            )
        else:
            triggered = should_giveback_close_v811(current_r, peak_r, arm_r, floor_r)

        if triggered:
            return index, current_r

    return None
