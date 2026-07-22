from __future__ import annotations

import pandas as pd
import pytest

from analysis.csv_io import CsvSchemaError
from analysis.parameter_stability import run, sweep_giveback_percent


# Hand-traced against ExitManager.mqh's EM_ShouldGivebackCloseV637 formula
# (effective_arm=max(0.25,arm_rr), trigger_r=peak_r*(1-pct/100), current<=trigger_r):
#
# Path B = [0.0, 2.0, 1.0, 0.5], actual_final_r = 0.5 (last value):
#   pct=40: trigger_r = 2.0*0.6 = 1.2 -> triggers at index2 (current=1.0<=1.2), r=1.0
#           r_diff = 1.0 - 0.5 = 0.5
#   pct=60: trigger_r = 2.0*0.4 = 0.8 -> triggers at index3 (current=0.5<=0.8), r=0.5
#           r_diff = 0.5 - 0.5 = 0.0
#   pct=80: trigger_r = 2.0*0.2 = 0.4 -> never triggers (0.5 > 0.4 at index3)
#           r_diff = 0.0 (no-trigger convention)
#
# Path C = [0.0, 1.25, 1.25], actual_final_r = 1.25:
#   peak reaches exactly 1.25 = effective_arm, but current==trigger_r never holds
#   for any percent > 0 (trigger_r always < 1.25 once armed) -> never triggers
#   at any of the three swept percents. r_diff = 0.0 always.
PATH_B = [0.0, 2.0, 1.0, 0.5]
PATH_C = [0.0, 1.25, 1.25]


def test_sweep_uses_full_path_set_not_just_triggered_subset():
    """Regression for a Codex review finding (2026-07-22): averaging only
    the TRIGGERED subset makes different giveback_percent settings
    incomparable (each triggers on a different subset). This test proves
    the mean is computed over the SAME full 2-path set at every percent."""

    rows = sweep_giveback_percent([PATH_B, PATH_C], [40.0, 60.0, 80.0])
    by_pct = {r.giveback_percent: r for r in rows}

    assert by_pct[40.0].n_triggered == 1
    assert by_pct[40.0].n_paths == 2
    assert by_pct[40.0].mean_r_diff_over_all_paths == pytest.approx(0.25)  # (0.5 + 0.0) / 2

    assert by_pct[60.0].n_triggered == 1
    assert by_pct[60.0].mean_r_diff_over_all_paths == pytest.approx(0.0)  # (0.0 + 0.0) / 2

    assert by_pct[80.0].n_triggered == 0
    assert by_pct[80.0].mean_r_diff_over_all_paths == pytest.approx(0.0)  # (0.0 + 0.0) / 2

    # Every row's mean is computed over n_paths == 2 -- the FULL set,
    # never a shrinking triggered-only subset.
    assert all(r.n_paths == 2 for r in rows)


def test_sweep_empty_r_paths_raises():
    with pytest.raises(ValueError):
        sweep_giveback_percent([], [40.0])


def test_sweep_empty_giveback_percents_raises():
    with pytest.raises(ValueError):
        sweep_giveback_percent([PATH_B], [])


def test_sweep_rejects_empty_path():
    with pytest.raises(ValueError):
        sweep_giveback_percent([[]], [40.0])


def test_sweep_ci_present_when_paths_vary():
    rows = sweep_giveback_percent([PATH_B, PATH_C], [40.0])
    assert rows[0].r_diff_ci_lower is not None
    assert rows[0].r_diff_ci_upper is not None


def test_sweep_ci_not_suppressed_for_constant_r_diffs():
    """Regression for a Codex review finding (2026-07-22, third round): a
    constant-r_diffs sample (e.g. the guard never triggers on any path)
    previously suppressed its own bootstrap CI entirely instead of
    reporting the exact, degenerate-but-valid interval
    bootstrap_confidence_interval already computes correctly for
    zero-variance data."""

    # pct=80 never triggers on either path (see module-level comment
    # above) -- both r_diffs are exactly 0.0, a constant sample.
    rows = sweep_giveback_percent([PATH_B, PATH_C], [80.0])
    assert rows[0].mean_r_diff_over_all_paths == pytest.approx(0.0)
    assert rows[0].r_diff_ci_lower is not None
    assert rows[0].r_diff_ci_upper is not None
    assert rows[0].r_diff_ci_lower == pytest.approx(0.0)
    assert rows[0].r_diff_ci_upper == pytest.approx(0.0)


def test_sweep_rejects_non_finite_r_path_value():
    with pytest.raises(ValueError):
        sweep_giveback_percent([[0.0, float("nan"), 1.0]], [40.0])


def test_sweep_rejects_non_finite_giveback_percent():
    with pytest.raises(ValueError):
        sweep_giveback_percent([PATH_B], [float("nan")])


def test_sweep_rejects_out_of_range_giveback_percent():
    """Regression for a Codex review finding (2026-07-22, third round):
    EM_ShouldGivebackCloseV637 silently clamps giveback_percent to
    [10, 90] -- a value outside that range was previously reported under
    its own out-of-range label while actually executing the clamped
    value, so distinct reported settings could execute the identical
    effective setting."""

    with pytest.raises(ValueError):
        sweep_giveback_percent([PATH_B], [5.0])  # below 10
    with pytest.raises(ValueError):
        sweep_giveback_percent([PATH_B], [95.0])  # above 90


def test_sweep_rejects_overflowing_mean_r_diff():
    """Regression for a Codex review finding (2026-07-22, fifth round):
    each individual r_diff (trigger_r - actual_final_r) is finite, but
    summing many extreme-but-finite r_diffs can still overflow -- two
    paths [2.0, 0.01, -1e308] each trigger early (trigger_r=0.01) against
    an actual_final_r of -1e308, giving a per-path diff of roughly 1e308;
    summing both previously produced a silent infinite mean with no
    guard."""

    extreme_path = [2.0, 0.01, -1e308]
    with pytest.raises(ValueError):
        sweep_giveback_percent([extreme_path, extreme_path], [60.0], arm_rr=1.25)


# --- run() (CSV wrapper) ------------------------------------------------------


def _write_r_paths_csv(path, paths: dict[str, list[float]]) -> None:
    rows = []
    for path_id, values in paths.items():
        for bar_index, r_value in enumerate(values):
            rows.append({"path_id": path_id, "bar_index": bar_index, "r_value": r_value})
    pd.DataFrame(rows).to_csv(path, index=False)


def test_run_reads_real_csv_and_reproduces_hand_traced_numbers(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    _write_r_paths_csv(r_paths_csv, {"pB": PATH_B, "pC": PATH_C})

    result = run(r_paths_csv, [40.0, 60.0, 80.0])
    by_pct = result.set_index("giveback_percent")
    assert by_pct.loc[40.0, "n_triggered"] == 1
    assert by_pct.loc[40.0, "mean_r_diff_over_all_paths"] == pytest.approx(0.25)


def test_run_writes_output_with_real_dataset_hash(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    _write_r_paths_csv(r_paths_csv, {"pB": PATH_B, "pC": PATH_C})
    summary_json = tmp_path / "out" / "summary.json"

    run(r_paths_csv, [40.0], summary_json=summary_json)

    import json

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"] != ""
    assert payload["metadata"]["pipeline_version"]


def test_run_zero_rows_raises(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    pd.DataFrame(columns=["path_id", "bar_index", "r_value"]).to_csv(r_paths_csv, index=False)
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0])


def test_run_non_finite_r_value_rejected(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    pd.DataFrame(
        {"path_id": ["p1", "p1"], "bar_index": [0, 1], "r_value": [0.0, float("nan")]}
    ).to_csv(r_paths_csv, index=False)
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0])


def test_run_output_path_colliding_with_input_rejected(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    _write_r_paths_csv(r_paths_csv, {"pB": PATH_B})
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0], output_csv=r_paths_csv)


def test_run_blank_path_id_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    a blank path_id previously vanished silently -- pandas' own groupby
    drops a blank/NaN key entirely rather than surfacing it as a schema
    error."""

    r_paths_csv = tmp_path / "r_paths.csv"
    pd.DataFrame({"path_id": ["", ""], "bar_index": [0, 1], "r_value": [0.0, 1.0]}).to_csv(
        r_paths_csv, index=False
    )
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0])


def test_run_malformed_bar_index_probe_rejected(tmp_path):
    """Regression for the exact malformed probe Codex reproduced
    (2026-07-22, fourth round): a blank path_id, a fractional/negative
    bar_index (-2.5), a duplicate bar_index (7 twice), and no bar_index 0
    all completed successfully before this fix."""

    r_paths_csv = tmp_path / "r_paths.csv"
    pd.DataFrame(
        {
            "path_id": ["p1", "p1", "p1"],
            "bar_index": [-2.5, 7, 7],
            "r_value": [0.5, 1.0, 1.0],
        }
    ).to_csv(r_paths_csv, index=False)
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0])


def test_run_duplicate_bar_index_rejected(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    pd.DataFrame(
        {"path_id": ["p1", "p1", "p1"], "bar_index": [0, 1, 1], "r_value": [0.0, 1.0, 2.0]}
    ).to_csv(r_paths_csv, index=False)
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0])


def test_run_missing_index_zero_rejected(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    pd.DataFrame({"path_id": ["p1", "p1"], "bar_index": [1, 2], "r_value": [0.5, 1.0]}).to_csv(
        r_paths_csv, index=False
    )
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0])


def test_run_nonzero_entry_r_rejected(tmp_path):
    """A trade starts at 0R by definition -- a nonzero entry (bar_index
    0) r_value is not a legitimate R-path."""

    r_paths_csv = tmp_path / "r_paths.csv"
    pd.DataFrame({"path_id": ["p1", "p1"], "bar_index": [0, 1], "r_value": [0.5, 1.0]}).to_csv(
        r_paths_csv, index=False
    )
    with pytest.raises(CsvSchemaError):
        run(r_paths_csv, [40.0])


def test_nan_arm_rr_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    neither arm_rr nor close_trigger_floor_r was validated -- NaN
    previously produced a "successful" result."""

    r_paths_csv = tmp_path / "r_paths.csv"
    _write_r_paths_csv(r_paths_csv, {"pB": PATH_B})
    with pytest.raises(ValueError):
        run(r_paths_csv, [40.0], arm_rr=float("nan"))


def test_nan_close_trigger_floor_r_rejected(tmp_path):
    r_paths_csv = tmp_path / "r_paths.csv"
    _write_r_paths_csv(r_paths_csv, {"pB": PATH_B})
    with pytest.raises(ValueError):
        run(r_paths_csv, [40.0], close_trigger_floor_r=float("nan"))


def test_summary_persists_arm_rr_and_bootstrap_config(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    arm_rr/close_trigger_floor_r and the bootstrap confidence/resample
    count were omitted from the summary despite being effective
    configuration for every row."""

    import json

    r_paths_csv = tmp_path / "r_paths.csv"
    _write_r_paths_csv(r_paths_csv, {"pB": PATH_B, "pC": PATH_C})
    summary_json = tmp_path / "summary.json"
    run(r_paths_csv, [40.0], summary_json=summary_json, arm_rr=1.5, close_trigger_floor_r=0.1)

    payload = json.loads(summary_json.read_text(encoding="utf-8"))
    assert payload["summary"]["arm_rr"] == 1.5
    assert payload["summary"]["close_trigger_floor_r"] == 0.1
    assert payload["summary"]["bootstrap_confidence"] == 0.95
    assert payload["summary"]["bootstrap_n_resamples"] == 2000
