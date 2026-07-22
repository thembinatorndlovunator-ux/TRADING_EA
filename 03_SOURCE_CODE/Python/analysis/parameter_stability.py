"""parameter_stability.py -- sweeps ExitManager.mqh's (TASK-030) V6.37-style
giveback-guard ``giveback_percent`` parameter across a set of historical (or
clearly-labelled synthetic) R-paths, reporting how the guard's effect on
mean R changes as the parameter varies.

**Provenance (Codex review finding, 2026-07-22):** this sweep previously
lived entirely inline inside notebook 06, in violation of this project's
own reproducibility contract rule 1 (every notebook needs a paired `.py`
pipeline). It also had a real statistical defect: it compared
``mean_r_diff_when_triggered`` across different ``giveback_percent``
settings, but each setting triggers on a DIFFERENT subset of paths (a
higher giveback_percent triggers later, or not at all, on some paths) --
averaging only over each setting's own triggered subset and then
comparing those means across settings is not a like-for-like comparison.

**Fixed here:** the mean R-diff is computed over the SAME FULL set of
paths for every parameter setting (a path where the guard never
triggers contributes an r_diff of 0.0 -- the same "no effect" convention
`analyse_giveback.py` already uses), so every row of the output table is
comparable to every other row.

**Fixed, 2026-07-22 Codex review finding (third round): this was NOT an
explicit-input reproducible pipeline** -- ``run()`` accepted only
caller-created in-memory R paths, the CLI accepted no input path at all
(always printed an error and exited 1), and hand-built metadata had no
dataset identity/hash. This module now reads R-paths from an explicit
CSV file (documented schema below), hashes it via the same
``build_report_metadata`` every other pipeline uses, and has a real,
functioning CLI.

Required input format: ``r_paths.csv`` columns: ``path_id, bar_index,
r_value`` -- one row per bar of one trade's chronological R-multiple
sequence (bar_index 0 = entry, increasing = later bars; the final
bar_index per path_id is that path's own "actual final R", matching
`analyse_giveback.py`'s own R-path convention). Rows are grouped by
path_id and sorted by bar_index to reconstruct each path.

**Extended, 2026-07-22 Codex review finding (fifth round):
`profit_giveback_diagnosis_plan.md` requires neighbouring sweeps of BOTH
V6.37 controls AND BOTH V8.11 controls -- this module previously
implemented only a one-dimensional V6.37 `giveback_percent` sweep.**
``sweep_v811_arm_and_floor``/``run_v811_sweep`` (new) add a genuine 2-D
grid sweep over V8.11's own two controls (`arm_r`, `floor_r`), using the
SAME `r_paths.csv` schema and the same like-for-like "mean over the full
path set" discipline as the V6.37 sweep. ``arm_rr``/``close_trigger_floor_r``
(V6.37) and ``arm_r``/``floor_r`` (V8.11) are now all validated against
their REAL model domain (not just finiteness) -- see
``MIN_V637_ARM_RR``/``MIN_V637_CLOSE_TRIGGER_FLOOR_R``/``MIN_V811_ARM_R``/
``MIN_V811_FLOOR_R``'s own comments for exactly which silent clamp each
one closes.

**Closed, 2026-07-22 Codex review finding (sixth round): the module
previously disclosed a full 2-D sweep of V6.37's OWN two controls
(`arm_rr` x `giveback_percent` together) as still missing -- the
canonical docs then went on to cite round-5 finding 9 as "fully
resolved" despite this module's own docstring saying otherwise (round-6
finding 11).** ``sweep_v637_arm_rr_and_giveback_percent``/
``run_v637_2d_sweep`` (new) add the genuine 2-D grid over V6.37's own two
controls, mirroring ``sweep_v811_arm_and_floor``'s structure and the same
like-for-like "mean over the full path set" discipline;
`sweep_giveback_percent` remains available unchanged for the narrower
one-dimensional case.

**Bar-boundary convention, disclosed but not yet unified across the
giveback family (Codex review finding, 2026-07-22, fifth round):** this
module's own schema requires `bar_index` 0 to be EXACTLY `0.0` (entry,
before any bar has closed) -- but `analyse_giveback.py` builds its
R-paths from bar CLOSE prices (its own index 0 already reflects the
entry bar's close, not a pre-bar `0.0`), and notebook 02's synthetic
fixtures begin a path at `+0.5R`. All three currently use a DIFFERENT
convention for what "index/bar 0" means. Picking one canonical
convention and updating the other two to match is a real, not-yet-done
follow-up; do not assume R-paths from these three sources are
interchangeable today.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from analysis.csv_io import (
    CsvSchemaError,
    assert_finite_columns,
    assert_output_paths_distinct,
    assert_path_not_same_file,
    assert_unique_composite_key,
    atomic_write_dataframe_csv,
    read_csv_with_required_columns_and_hash,
)
from analysis.exit_simulation import simulate_giveback_path
from analysis.metrics import MAX_N_RESAMPLES, MIN_N_RESAMPLES, bootstrap_confidence_interval
from analysis.report_metadata import atomic_write_text, build_report_metadata

REQUIRED_COLUMNS = {"path_id", "bar_index", "r_value"}
# ExitManager.mqh's EM_ShouldGivebackCloseV637 silently clamps giveback_percent
# to this range -- **fixed, 2026-07-22 Codex review finding (third round):
# a value outside this range was previously reported under the caller's own
# out-of-range label while actually executing the clamped value, so distinct
# reported settings could silently execute the identical effective setting.**
# Rejected outright now rather than silently clamped-and-mislabelled.
MIN_GIVEBACK_PERCENT = 10.0
MAX_GIVEBACK_PERCENT = 90.0
# **Added, 2026-07-22 Codex review finding (fifth round): arm_rr/
# close_trigger_floor_r were previously validated only for finiteness --
# EM_ShouldGivebackCloseV637 clamps arm_rr to `max(0.25, arm_rr)`, so a
# requested arm_rr of -5 and 0.25 silently produced IDENTICAL behavior
# while the artifact recorded -5 as if it were the effective arm.
# close_trigger_floor_r has no code-level clamp but a negative value
# contradicts the spec's own stated 0.05R floor and would let the guard
# trigger in negative-R territory, which is not a legitimate "floor".
# Both are now rejected outright when out of domain, matching the same
# reject-not-clamp discipline giveback_percent already has.**
MIN_V637_ARM_RR = 0.25
MIN_V637_CLOSE_TRIGGER_FLOOR_R = 0.0
# **Added, 2026-07-22 Codex review finding (fifth round): the V8.11
# equivalents -- EM_ShouldGivebackCloseV811 clamps arm_r to
# `max(0.3, arm_r)` and floor_r to `max(0.0, floor_r)`.**
MIN_V811_ARM_R = 0.3
MIN_V811_FLOOR_R = 0.0


@dataclass(frozen=True)
class StabilityRow:
    giveback_percent: float
    n_paths: int
    n_triggered: int
    mean_r_diff_over_all_paths: float
    r_diff_ci_lower: Optional[float]
    r_diff_ci_upper: Optional[float]


@dataclass(frozen=True)
class V811StabilityRow:
    """One row of a V8.11 (`arm_r`, `floor_r`) grid sweep -- see
    ``sweep_v811_arm_and_floor``'s own docstring."""

    arm_r: float
    floor_r: float
    n_paths: int
    n_triggered: int
    mean_r_diff_over_all_paths: float
    r_diff_ci_lower: Optional[float]
    r_diff_ci_upper: Optional[float]


@dataclass(frozen=True)
class V637TwoDStabilityRow:
    """One row of a V6.37 (`arm_rr`, `giveback_percent`) grid sweep -- see
    ``sweep_v637_arm_rr_and_giveback_percent``'s own docstring.

    **Added, 2026-07-22 Codex review finding (sixth round): the module's
    own docstring disclosed (and the canonical docs then wrongly
    described as "fully resolved" -- round-6 finding 11) that
    `profit_giveback_diagnosis_plan.md` requires a two-dimensional
    (`arm_rr`, `giveback_percent`) sweep for V6.37, matching the
    `V811StabilityRow` grid already built for V8.11 -- only
    ``sweep_giveback_percent``'s one-dimensional `giveback_percent` sweep
    (at a single fixed `arm_rr`) existed until now.**
    """

    arm_rr: float
    giveback_percent: float
    n_paths: int
    n_triggered: int
    mean_r_diff_over_all_paths: float
    r_diff_ci_lower: Optional[float]
    r_diff_ci_upper: Optional[float]


def _load_r_paths_from_csv(path: Path) -> tuple[list[list[float]], str]:
    """**Hardened, 2026-07-22 Codex review finding (fourth round): this
    previously enforced only bar_index/r_value finiteness -- a malformed
    probe with a blank path_id, a fractional/negative bar_index (-2.5), a
    duplicate bar_index (7 twice in one path), and no index 0 completed
    successfully. pandas' own ``groupby`` silently DROPS a blank-ID group
    entirely rather than surfacing it as a schema error.** Every one of
    those is now rejected outright.

    **Fixed, 2026-07-22 Codex review finding (sixth round): previously
    read via the plain (non-hashing) helper, then re-read a second time
    by each caller's own build_report_metadata call -- the same
    ABA-mutation race round 5 already closed for
    join_trade_journal.py/join_news_events.py/analyse_baseline.py but
    left open here. Returns the hash from this single read.**
    """

    # **Fixed, 2026-07-22 Codex review finding (seventh round, P1 finding
    # 15): path_id was previously read with pandas' own inferred dtype --
    # a CSV containing purely-numeric-looking path_id values (e.g. "001"
    # and "1") silently collapsed to the SAME numeric value (leading
    # zeroes discarded), exactly the durable-identifier dtype bug
    # 'read_csv_with_required_columns_and_hash' already documents its own
    # 'dtype' parameter exists to prevent (see csv_io.py) -- this call
    # simply never used it for 'path_id'.**
    df, file_hash = read_csv_with_required_columns_and_hash(
        path, REQUIRED_COLUMNS, dtype={"path_id": str}
    )
    if df.empty:
        raise CsvSchemaError(f"{path}: zero rows")
    assert_finite_columns(df, ["bar_index", "r_value"], path)

    blank_mask = df["path_id"].isna() | (df["path_id"].astype(str).str.strip() == "")
    if blank_mask.any():
        raise CsvSchemaError(
            f"{path}: {int(blank_mask.sum())} row(s) have a null/blank path_id: "
            f"rows {df.index[blank_mask].tolist()}"
        )

    assert_unique_composite_key(df, ["path_id", "bar_index"], path)

    non_integer_mask = df["bar_index"] != df["bar_index"].round()
    if non_integer_mask.any():
        raise CsvSchemaError(
            f"{path}: bar_index must be an integer, got fractional values at rows "
            f"{df.index[non_integer_mask].tolist()}"
        )
    if (df["bar_index"] < 0).any():
        raise CsvSchemaError(f"{path}: bar_index must be non-negative")

    paths: list[list[float]] = []
    for path_id, group in df.sort_values(["path_id", "bar_index"]).groupby("path_id", sort=False):
        bar_indices = group["bar_index"].tolist()
        expected = list(range(len(bar_indices)))
        if [int(b) for b in bar_indices] != expected:
            raise CsvSchemaError(
                f"{path}: path_id={path_id!r} bar_index sequence must be contiguous starting at "
                f"0 (0, 1, 2, ...), got {bar_indices}"
            )
        r_values = group["r_value"].tolist()
        # A trade starts at 0R by definition (simulate_giveback_path's own
        # peak_r=0.0 assumption) -- a nonzero entry R is not a legitimate
        # R-path, not silently accepted as one.
        if r_values[0] != 0.0:
            raise CsvSchemaError(
                f"{path}: path_id={path_id!r} entry (bar_index 0) r_value must be 0.0, "
                f"got {r_values[0]}"
            )
        paths.append(r_values)
    return paths, file_hash


def sweep_giveback_percent(
    r_paths: Sequence[Sequence[float]],
    giveback_percents: Sequence[float],
    *,
    arm_rr: float = 1.25,
    close_trigger_floor_r: float = 0.05,
    seed: int = 42,
    # **Added, 2026-07-22 Codex review finding (fifth round): the
    # bootstrap call below previously hard-coded n_resamples=2000/
    # confidence=0.95 (bootstrap_confidence_interval's own defaults),
    # with no way for a caller to override or discover what was used --
    # matching the same gap already fixed in analyse_giveback.py.**
    n_resamples: int = 2000,
    confidence: float = 0.95,
) -> list[StabilityRow]:
    """For each value in 'giveback_percents', simulates the V6.37 giveback
    guard against every path in 'r_paths' (each path's actual final R is
    its own last value -- these are already-completed historical/synthetic
    R sequences, not live trades), and computes the mean R-diff over the
    FULL set of paths (0.0 contribution for any path the guard never
    triggers on) -- see module docstring for why this differs from
    averaging only the triggered subset.

    Raises ValueError if 'r_paths' or 'giveback_percents' is empty, any
    path is empty or contains a non-finite value, or any percent is
    non-finite or outside [10, 90] (the range
    ``EM_ShouldGivebackCloseV637`` actually honors without silently
    clamping to a different effective value).
    """

    if not r_paths:
        raise ValueError("sweep_giveback_percent: r_paths must not be empty")
    # **Added, 2026-07-22 Codex review finding (fifth round): validated
    # UNCONDITIONALLY here rather than only inside the per-row bootstrap
    # branch below, matching the same fix already applied to
    # analyse_giveback.py/performance_breakdown.py/walk_forward.py --
    # bad n_resamples/confidence must be rejected even if every row
    # happens to have fewer than 2 paths and never reaches that branch.**
    if not (0.0 < confidence < 1.0):
        raise ValueError(f"sweep_giveback_percent: confidence must be in (0, 1), got {confidence}")
    if not (MIN_N_RESAMPLES <= n_resamples <= MAX_N_RESAMPLES):
        raise ValueError(
            f"sweep_giveback_percent: n_resamples must be in [{MIN_N_RESAMPLES}, "
            f"{MAX_N_RESAMPLES}], got {n_resamples}"
        )
    if not giveback_percents:
        raise ValueError("sweep_giveback_percent: giveback_percents must not be empty")
    if any(not p for p in r_paths):
        raise ValueError("sweep_giveback_percent: every path in r_paths must be non-empty")
    if any(not math.isfinite(v) for p in r_paths for v in p):
        raise ValueError("sweep_giveback_percent: every r_path value must be finite")
    # **Added, 2026-07-22 Codex review finding (fourth round):** neither
    # arm_rr nor close_trigger_floor_r was validated or CLI-exposed --
    # a NaN value for either previously produced a "successful" result
    # (should_giveback_close_v637's own max()/min() clamps silently
    # substitute an effective value for a NaN input).
    if not math.isfinite(arm_rr):
        raise ValueError(f"sweep_giveback_percent: arm_rr must be finite, got {arm_rr}")
    if not math.isfinite(close_trigger_floor_r):
        raise ValueError(
            f"sweep_giveback_percent: close_trigger_floor_r must be finite, got {close_trigger_floor_r}"
        )
    # **Added, 2026-07-22 Codex review finding (fifth round): finiteness
    # alone is not the real model domain -- see MIN_V637_ARM_RR/
    # MIN_V637_CLOSE_TRIGGER_FLOOR_R's own comment.**
    if arm_rr < MIN_V637_ARM_RR:
        raise ValueError(
            f"sweep_giveback_percent: arm_rr {arm_rr} is below {MIN_V637_ARM_RR} -- "
            "EM_ShouldGivebackCloseV637 would silently clamp it to a different EFFECTIVE "
            "value, so an out-of-domain setting must be rejected rather than reported "
            "under its own requested label"
        )
    if close_trigger_floor_r < MIN_V637_CLOSE_TRIGGER_FLOOR_R:
        raise ValueError(
            f"sweep_giveback_percent: close_trigger_floor_r {close_trigger_floor_r} is below "
            f"{MIN_V637_CLOSE_TRIGGER_FLOOR_R} -- a negative floor contradicts the spec's own "
            "stated non-negative floor and would let the guard trigger in negative-R territory"
        )
    for pct in giveback_percents:
        if not math.isfinite(pct):
            raise ValueError(f"sweep_giveback_percent: giveback_percent must be finite, got {pct}")
        if not (MIN_GIVEBACK_PERCENT <= pct <= MAX_GIVEBACK_PERCENT):
            raise ValueError(
                f"sweep_giveback_percent: giveback_percent {pct} outside "
                f"[{MIN_GIVEBACK_PERCENT}, {MAX_GIVEBACK_PERCENT}] -- EM_ShouldGivebackCloseV637 "
                "would silently clamp it to a different EFFECTIVE value, so an out-of-range "
                "setting must be rejected rather than reported under its own requested label"
            )

    rows: list[StabilityRow] = []
    for pct in giveback_percents:
        r_diffs: list[float] = []
        n_triggered = 0
        for path in r_paths:
            actual_final_r = path[-1]
            triggered = simulate_giveback_path(
                path,
                "v637",
                arm_rr=arm_rr,
                giveback_percent=pct,
                close_trigger_floor_r=close_trigger_floor_r,
            )
            if triggered is not None:
                n_triggered += 1
                _, trigger_r = triggered
                r_diffs.append(trigger_r - actual_final_r)
            else:
                r_diffs.append(0.0)  # same "no effect" convention as analyse_giveback.py

        mean_r_diff = sum(r_diffs) / len(r_diffs)
        # **Added, 2026-07-22 Codex review finding (fifth round):** each
        # individual r_diff is finite (a bounded R-multiple difference in
        # ordinary use), but summing many extreme values can still
        # overflow to +/-inf -- two finite stability paths ending at
        # -1e308 previously produced an infinite mean with no guard here.
        if not math.isfinite(mean_r_diff):
            raise ValueError(
                f"sweep_giveback_percent: mean_r_diff_over_all_paths overflowed to a non-finite "
                f"value ({mean_r_diff}) at giveback_percent={pct} -- individual r_diffs are "
                "finite but their sum/mean is not"
            )
        ci_lower = ci_upper = None
        # **Fixed, 2026-07-22 Codex review finding (third round): a
        # constant-r_diffs sample (e.g. the guard never triggers on any
        # path) previously SUPPRESSED its own bootstrap CI entirely
        # instead of reporting the exact (degenerate but valid) interval
        # bootstrap_confidence_interval already computes correctly for
        # zero-variance data -- see its own test coverage.**
        if len(r_diffs) >= 2:
            boot = bootstrap_confidence_interval(
                r_diffs,
                statistic="mean",
                seed=seed,
                n_resamples=n_resamples,
                confidence=confidence,
            )
            ci_lower, ci_upper = boot.ci_lower, boot.ci_upper

        rows.append(
            StabilityRow(
                giveback_percent=pct,
                n_paths=len(r_paths),
                n_triggered=n_triggered,
                mean_r_diff_over_all_paths=mean_r_diff,
                r_diff_ci_lower=ci_lower,
                r_diff_ci_upper=ci_upper,
            )
        )
    return rows


def sweep_v637_arm_rr_and_giveback_percent(
    r_paths: Sequence[Sequence[float]],
    arm_rr_values: Sequence[float],
    giveback_percents: Sequence[float],
    *,
    close_trigger_floor_r: float = 0.05,
    seed: int = 42,
    n_resamples: int = 2000,
    confidence: float = 0.95,
) -> list[V637TwoDStabilityRow]:
    """**Added, 2026-07-22 Codex review finding (sixth round):
    `profit_giveback_diagnosis_plan.md` requires neighbouring sweeps of
    BOTH V6.37 controls (`arm_rr`, `giveback_percent`), not just a
    one-dimensional `giveback_percent` sweep at a single fixed `arm_rr`
    (``sweep_giveback_percent``, still available for that narrower use)
    -- this was previously entirely unimplemented, and the module's own
    disclosure of that gap was subsequently mis-cited by the canonical
    docs as "fully resolved".** For every (arm_rr, giveback_percent) pair
    in the cartesian product of 'arm_rr_values' x 'giveback_percents',
    simulates the V6.37 giveback guard against every path in 'r_paths'
    and computes the mean R-diff over the SAME FULL set of paths (0.0
    contribution for any path the guard never triggers on) -- identical
    like-for-like discipline to ``sweep_giveback_percent``/
    ``sweep_v811_arm_and_floor``, so every row of this grid is comparable
    to every other row, including across all three tables.
    'close_trigger_floor_r' is held fixed across the whole grid (as
    ``sweep_giveback_percent`` already does for a single 'arm_rr'), since
    the diagnosis plan only requires a 2-D grid over the other two
    controls.

    Raises ValueError if 'r_paths', 'arm_rr_values', or
    'giveback_percents' is empty, any path is empty or contains a
    non-finite value, or any arm_rr/giveback_percent/close_trigger_floor_r
    is non-finite or outside the real model domain (see
    MIN_V637_ARM_RR/MIN_V637_CLOSE_TRIGGER_FLOOR_R/MIN_GIVEBACK_PERCENT/
    MAX_GIVEBACK_PERCENT's own comments) -- same domain-rejection
    discipline as ``sweep_giveback_percent``.
    """

    if not r_paths:
        raise ValueError("sweep_v637_arm_rr_and_giveback_percent: r_paths must not be empty")
    if not (0.0 < confidence < 1.0):
        raise ValueError(
            f"sweep_v637_arm_rr_and_giveback_percent: confidence must be in (0, 1), "
            f"got {confidence}"
        )
    if not (MIN_N_RESAMPLES <= n_resamples <= MAX_N_RESAMPLES):
        raise ValueError(
            f"sweep_v637_arm_rr_and_giveback_percent: n_resamples must be in "
            f"[{MIN_N_RESAMPLES}, {MAX_N_RESAMPLES}], got {n_resamples}"
        )
    if not arm_rr_values:
        raise ValueError("sweep_v637_arm_rr_and_giveback_percent: arm_rr_values must not be empty")
    if not giveback_percents:
        raise ValueError(
            "sweep_v637_arm_rr_and_giveback_percent: giveback_percents must not be empty"
        )
    if any(not p for p in r_paths):
        raise ValueError(
            "sweep_v637_arm_rr_and_giveback_percent: every path in r_paths must be non-empty"
        )
    if any(not math.isfinite(v) for p in r_paths for v in p):
        raise ValueError(
            "sweep_v637_arm_rr_and_giveback_percent: every r_path value must be finite"
        )
    if not math.isfinite(close_trigger_floor_r):
        raise ValueError(
            "sweep_v637_arm_rr_and_giveback_percent: close_trigger_floor_r must be finite, "
            f"got {close_trigger_floor_r}"
        )
    if close_trigger_floor_r < MIN_V637_CLOSE_TRIGGER_FLOOR_R:
        raise ValueError(
            f"sweep_v637_arm_rr_and_giveback_percent: close_trigger_floor_r "
            f"{close_trigger_floor_r} is below {MIN_V637_CLOSE_TRIGGER_FLOOR_R} -- a negative "
            "floor contradicts the spec's own stated non-negative floor and would let the "
            "guard trigger in negative-R territory"
        )
    for arm_rr in arm_rr_values:
        if not math.isfinite(arm_rr):
            raise ValueError(
                f"sweep_v637_arm_rr_and_giveback_percent: arm_rr must be finite, got {arm_rr}"
            )
        if arm_rr < MIN_V637_ARM_RR:
            raise ValueError(
                f"sweep_v637_arm_rr_and_giveback_percent: arm_rr {arm_rr} is below "
                f"{MIN_V637_ARM_RR} -- EM_ShouldGivebackCloseV637 would silently clamp it to a "
                "different EFFECTIVE value, so an out-of-domain setting must be rejected "
                "rather than reported under its own requested label"
            )
    for pct in giveback_percents:
        if not math.isfinite(pct):
            raise ValueError(
                f"sweep_v637_arm_rr_and_giveback_percent: giveback_percent must be finite, "
                f"got {pct}"
            )
        if not (MIN_GIVEBACK_PERCENT <= pct <= MAX_GIVEBACK_PERCENT):
            raise ValueError(
                f"sweep_v637_arm_rr_and_giveback_percent: giveback_percent {pct} outside "
                f"[{MIN_GIVEBACK_PERCENT}, {MAX_GIVEBACK_PERCENT}] -- EM_ShouldGivebackCloseV637 "
                "would silently clamp it to a different EFFECTIVE value, so an out-of-range "
                "setting must be rejected rather than reported under its own requested label"
            )

    rows: list[V637TwoDStabilityRow] = []
    for arm_rr in arm_rr_values:
        for pct in giveback_percents:
            r_diffs: list[float] = []
            n_triggered = 0
            for path in r_paths:
                actual_final_r = path[-1]
                triggered = simulate_giveback_path(
                    path,
                    "v637",
                    arm_rr=arm_rr,
                    giveback_percent=pct,
                    close_trigger_floor_r=close_trigger_floor_r,
                )
                if triggered is not None:
                    n_triggered += 1
                    _, trigger_r = triggered
                    r_diffs.append(trigger_r - actual_final_r)
                else:
                    r_diffs.append(0.0)  # same "no effect" convention as the other sweeps

            mean_r_diff = sum(r_diffs) / len(r_diffs)
            if not math.isfinite(mean_r_diff):
                raise ValueError(
                    f"sweep_v637_arm_rr_and_giveback_percent: mean_r_diff_over_all_paths "
                    f"overflowed to a non-finite value ({mean_r_diff}) at arm_rr={arm_rr}, "
                    f"giveback_percent={pct} -- individual r_diffs are finite but their "
                    "sum/mean is not"
                )
            ci_lower = ci_upper = None
            if len(r_diffs) >= 2:
                boot = bootstrap_confidence_interval(
                    r_diffs,
                    statistic="mean",
                    seed=seed,
                    n_resamples=n_resamples,
                    confidence=confidence,
                )
                ci_lower, ci_upper = boot.ci_lower, boot.ci_upper

            rows.append(
                V637TwoDStabilityRow(
                    arm_rr=arm_rr,
                    giveback_percent=pct,
                    n_paths=len(r_paths),
                    n_triggered=n_triggered,
                    mean_r_diff_over_all_paths=mean_r_diff,
                    r_diff_ci_lower=ci_lower,
                    r_diff_ci_upper=ci_upper,
                )
            )
    return rows


def sweep_v811_arm_and_floor(
    r_paths: Sequence[Sequence[float]],
    arm_r_values: Sequence[float],
    floor_r_values: Sequence[float],
    *,
    seed: int = 42,
    n_resamples: int = 2000,
    confidence: float = 0.95,
) -> list[V811StabilityRow]:
    """**Added, 2026-07-22 Codex review finding (fifth round):
    `profit_giveback_diagnosis_plan.md` requires neighbouring sweeps of
    BOTH V8.11 controls (`arm_r`, `floor_r`), not just a one-dimensional
    V6.37 `giveback_percent` sweep -- this was previously entirely
    unimplemented.** For every (arm_r, floor_r) pair in the cartesian
    product of 'arm_r_values' x 'floor_r_values', simulates the V8.11
    giveback guard against every path in 'r_paths' and computes the mean
    R-diff over the SAME FULL set of paths (0.0 contribution for any path
    the guard never triggers on) -- identical like-for-like discipline to
    ``sweep_giveback_percent``, so every row of the output grid is
    comparable to every other row, including across the two models'
    otherwise-separate tables.

    Raises ValueError if 'r_paths', 'arm_r_values', or 'floor_r_values' is
    empty, any path is empty or contains a non-finite value, or any
    arm_r/floor_r is non-finite or below the real model domain
    (``EM_ShouldGivebackCloseV811`` clamps arm_r to `max(0.3, arm_r)` and
    floor_r to `max(0.0, floor_r)` -- an out-of-domain requested value is
    rejected outright rather than silently executed under a different
    effective value, same discipline as V6.37's own giveback_percent).
    """

    if not r_paths:
        raise ValueError("sweep_v811_arm_and_floor: r_paths must not be empty")
    if not (0.0 < confidence < 1.0):
        raise ValueError(
            f"sweep_v811_arm_and_floor: confidence must be in (0, 1), got {confidence}"
        )
    if not (MIN_N_RESAMPLES <= n_resamples <= MAX_N_RESAMPLES):
        raise ValueError(
            f"sweep_v811_arm_and_floor: n_resamples must be in [{MIN_N_RESAMPLES}, "
            f"{MAX_N_RESAMPLES}], got {n_resamples}"
        )
    if not arm_r_values:
        raise ValueError("sweep_v811_arm_and_floor: arm_r_values must not be empty")
    if not floor_r_values:
        raise ValueError("sweep_v811_arm_and_floor: floor_r_values must not be empty")
    if any(not p for p in r_paths):
        raise ValueError("sweep_v811_arm_and_floor: every path in r_paths must be non-empty")
    if any(not math.isfinite(v) for p in r_paths for v in p):
        raise ValueError("sweep_v811_arm_and_floor: every r_path value must be finite")
    for arm_r in arm_r_values:
        if not math.isfinite(arm_r):
            raise ValueError(f"sweep_v811_arm_and_floor: arm_r must be finite, got {arm_r}")
        if arm_r < MIN_V811_ARM_R:
            raise ValueError(
                f"sweep_v811_arm_and_floor: arm_r {arm_r} is below {MIN_V811_ARM_R} -- "
                "EM_ShouldGivebackCloseV811 would silently clamp it to a different EFFECTIVE "
                "value, so an out-of-domain setting must be rejected rather than reported "
                "under its own requested label"
            )
    for floor_r in floor_r_values:
        if not math.isfinite(floor_r):
            raise ValueError(f"sweep_v811_arm_and_floor: floor_r must be finite, got {floor_r}")
        if floor_r < MIN_V811_FLOOR_R:
            raise ValueError(
                f"sweep_v811_arm_and_floor: floor_r {floor_r} is below {MIN_V811_FLOOR_R} -- "
                "EM_ShouldGivebackCloseV811 would silently clamp it to a different EFFECTIVE "
                "value, so an out-of-domain setting must be rejected rather than reported "
                "under its own requested label"
            )

    rows: list[V811StabilityRow] = []
    for arm_r in arm_r_values:
        for floor_r in floor_r_values:
            r_diffs: list[float] = []
            n_triggered = 0
            for path in r_paths:
                actual_final_r = path[-1]
                triggered = simulate_giveback_path(path, "v811", arm_r=arm_r, floor_r=floor_r)
                if triggered is not None:
                    n_triggered += 1
                    _, trigger_r = triggered
                    r_diffs.append(trigger_r - actual_final_r)
                else:
                    r_diffs.append(0.0)  # same "no effect" convention as sweep_giveback_percent

            mean_r_diff = sum(r_diffs) / len(r_diffs)
            if not math.isfinite(mean_r_diff):
                raise ValueError(
                    f"sweep_v811_arm_and_floor: mean_r_diff_over_all_paths overflowed to a "
                    f"non-finite value ({mean_r_diff}) at arm_r={arm_r}, floor_r={floor_r} -- "
                    "individual r_diffs are finite but their sum/mean is not"
                )
            ci_lower = ci_upper = None
            if len(r_diffs) >= 2:
                boot = bootstrap_confidence_interval(
                    r_diffs,
                    statistic="mean",
                    seed=seed,
                    n_resamples=n_resamples,
                    confidence=confidence,
                )
                ci_lower, ci_upper = boot.ci_lower, boot.ci_upper

            rows.append(
                V811StabilityRow(
                    arm_r=arm_r,
                    floor_r=floor_r,
                    n_paths=len(r_paths),
                    n_triggered=n_triggered,
                    mean_r_diff_over_all_paths=mean_r_diff,
                    r_diff_ci_lower=ci_lower,
                    r_diff_ci_upper=ci_upper,
                )
            )
    return rows


def run(
    r_paths_csv: Path,
    giveback_percents: Sequence[float],
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    arm_rr: float = 1.25,
    close_trigger_floor_r: float = 0.05,
    seed: int = 42,
    n_resamples: int = 2000,
    confidence: float = 0.95,
    symbol: Optional[str] = None,
    # **Added, 2026-07-22 Codex review finding (fourth round): spread_note/
    # slippage_note exist on ReportMetadata but no analysis caller exposed
    # or populated them.**
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """Reads R-paths from 'r_paths_csv' (see module docstring for the
    schema) and sweeps 'giveback_percents' against them. Raises
    CsvSchemaError for structural input problems, ValueError for
    invalid parameter values (see sweep_giveback_percent's docstring).
    """

    # **Added, 2026-07-22 Codex review finding (sixth round): a caller
    # requesting output_csv without summary_json previously got a CSV
    # with NO accompanying provenance metadata anywhere. An implicit
    # sidecar path is now derived (matching join_trade_journal.py/
    # join_news_events.py/join_signal_to_outcome.py's own pattern),
    # derived FIRST so the collision checks below cover it too.**
    if summary_json is None and output_csv is not None:
        summary_json = output_csv.parent / f"{output_csv.stem}.summary.json"

    # **Fixed, 2026-07-22 Codex review finding (fourth round): this guard
    # used a bare Path.resolve() == comparison, which a hard link to
    # r_paths_csv (different resolved name, identical underlying file)
    # would bypass -- every other pipeline in this layer already uses the
    # OS-level file-identity check.**
    for out_path in (output_csv, summary_json):
        assert_path_not_same_file(out_path, r_paths_csv, "output path")
    assert_output_paths_distinct([output_csv, summary_json])

    r_paths, r_paths_csv_hash = _load_r_paths_from_csv(r_paths_csv)
    rows = sweep_giveback_percent(
        r_paths,
        giveback_percents,
        arm_rr=arm_rr,
        close_trigger_floor_r=close_trigger_floor_r,
        seed=seed,
        n_resamples=n_resamples,
        confidence=confidence,
    )
    result = pd.DataFrame([r.__dict__ for r in rows])

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(result, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [r_paths_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=r_paths_csv_hash,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_paths": len(r_paths),
                "giveback_percents_swept": list(giveback_percents),
                "seed": seed,
                # **Added, 2026-07-22 Codex review finding (fourth round):**
                # arm_rr/close_trigger_floor_r were effective configuration
                # for every row of this sweep but were never persisted, and
                # the bootstrap confidence/resample count used for every
                # row's CI was likewise omitted.
                "arm_rr": arm_rr,
                "close_trigger_floor_r": close_trigger_floor_r,
                # **Fixed, 2026-07-22 Codex review finding (fifth round):**
                # these previously hard-coded the LITERALS 0.95/2000
                # regardless of what was actually passed to
                # sweep_giveback_percent, silently lying to a caller who
                # overrode either.
                "bootstrap_confidence": confidence,
                "bootstrap_n_resamples": n_resamples,
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def run_v811_sweep(
    r_paths_csv: Path,
    arm_r_values: Sequence[float],
    floor_r_values: Sequence[float],
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    seed: int = 42,
    n_resamples: int = 2000,
    confidence: float = 0.95,
    symbol: Optional[str] = None,
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """As ``run()``, but for ``sweep_v811_arm_and_floor`` -- reads the SAME
    ``r_paths.csv`` schema and runs the V8.11 (arm_r, floor_r) grid sweep
    instead of V6.37's giveback_percent sweep (added, 2026-07-22 Codex
    review finding, fifth round: `profit_giveback_diagnosis_plan.md`
    requires both models' neighbouring sweeps, not V6.37 alone).
    """

    # **Added, 2026-07-22 Codex review finding (sixth round): see
    # run()'s own comment above -- the same implicit-sidecar gap existed
    # here.**
    if summary_json is None and output_csv is not None:
        summary_json = output_csv.parent / f"{output_csv.stem}.summary.json"

    for out_path in (output_csv, summary_json):
        assert_path_not_same_file(out_path, r_paths_csv, "output path")
    assert_output_paths_distinct([output_csv, summary_json])

    r_paths, r_paths_csv_hash = _load_r_paths_from_csv(r_paths_csv)
    rows = sweep_v811_arm_and_floor(
        r_paths,
        arm_r_values,
        floor_r_values,
        seed=seed,
        n_resamples=n_resamples,
        confidence=confidence,
    )
    result = pd.DataFrame([r.__dict__ for r in rows])

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(result, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [r_paths_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=r_paths_csv_hash,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_paths": len(r_paths),
                "arm_r_values_swept": list(arm_r_values),
                "floor_r_values_swept": list(floor_r_values),
                "seed": seed,
                "bootstrap_confidence": confidence,
                "bootstrap_n_resamples": n_resamples,
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def run_v637_2d_sweep(
    r_paths_csv: Path,
    arm_rr_values: Sequence[float],
    giveback_percents: Sequence[float],
    output_csv: Optional[Path] = None,
    summary_json: Optional[Path] = None,
    *,
    close_trigger_floor_r: float = 0.05,
    seed: int = 42,
    n_resamples: int = 2000,
    confidence: float = 0.95,
    symbol: Optional[str] = None,
    spread_note: Optional[str] = None,
    slippage_note: Optional[str] = None,
    repo_path: Optional[Path] = None,
) -> pd.DataFrame:
    """As ``run_v811_sweep``, but for
    ``sweep_v637_arm_rr_and_giveback_percent`` -- reads the SAME
    ``r_paths.csv`` schema and runs the V6.37 (arm_rr, giveback_percent)
    grid sweep (added, 2026-07-22 Codex review finding, sixth round: the
    V6.37 half of `profit_giveback_diagnosis_plan.md`'s required
    neighbouring-sweep pair, previously still entirely unimplemented
    despite round 5's V8.11 grid).
    """

    if summary_json is None and output_csv is not None:
        summary_json = output_csv.parent / f"{output_csv.stem}.summary.json"

    for out_path in (output_csv, summary_json):
        assert_path_not_same_file(out_path, r_paths_csv, "output path")
    assert_output_paths_distinct([output_csv, summary_json])

    r_paths, r_paths_csv_hash = _load_r_paths_from_csv(r_paths_csv)
    rows = sweep_v637_arm_rr_and_giveback_percent(
        r_paths,
        arm_rr_values,
        giveback_percents,
        close_trigger_floor_r=close_trigger_floor_r,
        seed=seed,
        n_resamples=n_resamples,
        confidence=confidence,
    )
    result = pd.DataFrame([r.__dict__ for r in rows])

    if output_csv is not None:
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_dataframe_csv(result, output_csv)

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        metadata = build_report_metadata(
            [r_paths_csv],
            symbol=symbol,
            random_seed=seed,
            spread_note=spread_note,
            slippage_note=slippage_note,
            repo_path=repo_path,
            dataset_hash_override=r_paths_csv_hash,
        )
        payload = {
            "metadata": metadata.to_dict(),
            "summary": {
                "n_paths": len(r_paths),
                "arm_rr_values_swept": list(arm_rr_values),
                "giveback_percents_swept": list(giveback_percents),
                "close_trigger_floor_r": close_trigger_floor_r,
                "seed": seed,
                "bootstrap_confidence": confidence,
                "bootstrap_n_resamples": n_resamples,
            },
        }
        atomic_write_text(summary_json, json.dumps(payload, indent=2, default=str, allow_nan=False))

    return result


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--r-paths-csv", required=True, type=Path)
    parser.add_argument("--output-csv", type=Path, default=None)
    parser.add_argument("--summary-json", type=Path, default=None)
    # **Added, 2026-07-22 Codex review finding (fifth round): selects
    # which model's sweep to run -- V6.37's one-dimensional
    # giveback_percent sweep (unchanged, still the default for backward
    # compatibility), the V8.11 (arm_r, floor_r) grid sweep, or (added,
    # sixth round) the V6.37 (arm_rr, giveback_percent) grid sweep.**
    parser.add_argument("--model", choices=["v637", "v811", "v637_2d"], default="v637")
    parser.add_argument("--giveback-percents", type=float, nargs="+", default=[40.0, 60.0, 80.0])
    # **Added, 2026-07-22 Codex review finding (fourth round): neither was
    # previously CLI-exposed, despite being effective configuration for
    # every row of the sweep.**
    parser.add_argument("--arm-rr", type=float, default=1.25)
    parser.add_argument("--close-trigger-floor-r", type=float, default=0.05)
    # **Added, 2026-07-22 Codex review finding (fifth round): V8.11's own
    # two controls, only used when --model=v811.**
    parser.add_argument("--arm-r-values", type=float, nargs="+", default=[0.5, 0.8, 1.1])
    parser.add_argument("--floor-r-values", type=float, nargs="+", default=[0.0, 0.1, 0.2])
    # **Added, 2026-07-22 Codex review finding (sixth round): V6.37's own
    # 2-D grid values, only used when --model=v637_2d.**
    parser.add_argument("--arm-rr-values", type=float, nargs="+", default=[1.0, 1.25, 1.5])
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--n-resamples", type=int, default=2000)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--symbol", default=None)
    parser.add_argument("--spread-note", default=None)
    parser.add_argument("--slippage-note", default=None)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_arg_parser().parse_args(argv)
    try:
        if args.model == "v811":
            result = run_v811_sweep(
                r_paths_csv=args.r_paths_csv,
                arm_r_values=args.arm_r_values,
                floor_r_values=args.floor_r_values,
                output_csv=args.output_csv,
                summary_json=args.summary_json,
                seed=args.seed,
                n_resamples=args.n_resamples,
                confidence=args.confidence,
                symbol=args.symbol,
                spread_note=args.spread_note,
                slippage_note=args.slippage_note,
            )
        elif args.model == "v637_2d":
            result = run_v637_2d_sweep(
                r_paths_csv=args.r_paths_csv,
                arm_rr_values=args.arm_rr_values,
                giveback_percents=args.giveback_percents,
                output_csv=args.output_csv,
                summary_json=args.summary_json,
                close_trigger_floor_r=args.close_trigger_floor_r,
                seed=args.seed,
                n_resamples=args.n_resamples,
                confidence=args.confidence,
                symbol=args.symbol,
                spread_note=args.spread_note,
                slippage_note=args.slippage_note,
            )
        else:
            result = run(
                r_paths_csv=args.r_paths_csv,
                giveback_percents=args.giveback_percents,
                output_csv=args.output_csv,
                summary_json=args.summary_json,
                arm_rr=args.arm_rr,
                close_trigger_floor_r=args.close_trigger_floor_r,
                seed=args.seed,
                n_resamples=args.n_resamples,
                confidence=args.confidence,
                symbol=args.symbol,
                spread_note=args.spread_note,
                slippage_note=args.slippage_note,
            )
    except (FileNotFoundError, CsvSchemaError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"parameter_stability ({args.model}): {len(result)} settings swept.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
