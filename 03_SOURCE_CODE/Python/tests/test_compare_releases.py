from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.compare_releases import (
    MIN_N_PER_GROUP,
    MIN_N_RESAMPLES,
    main,
    run,
    two_sample_bootstrap_diff,
)
from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError

REPO_ROOT = Path(__file__).resolve().parents[3]

# **Added, 2026-07-22 Codex review finding (fourth round): period_start/
# period_end are now required run() parameters -- a wide default window
# covering every fixture's default 2026-07-21 entry/exit timestamps below.**
DEFAULT_PERIOD_START = "2026-01-01T00:00:00Z"
DEFAULT_PERIOD_END = "2026-12-31T23:59:59Z"


def _write_trades(
    path: Path, exits: list[float], profits: list[float], symbol: str = "XAUUSD"
) -> None:
    rows = []
    for i, (exit_price, profit) in enumerate(zip(exits, profits)):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": symbol,
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": exit_price,
                "stop_price": 98.0,
                "profit": profit,
            }
        )
    pd.DataFrame(rows).to_csv(path, index=False)


# --- two_sample_bootstrap_diff -------------------------------------------------


def test_insufficient_sample_below_min_n_per_group_raises():
    """Regression for a Codex review finding: previously only required
    n>=2 per group, which let a degenerate 2-observation sample "bless"
    a fake significant result (see test below)."""

    with pytest.raises(InsufficientSampleError):
        two_sample_bootstrap_diff(
            [1.0] * (MIN_N_PER_GROUP - 1),
            [1.0] * MIN_N_PER_GROUP,
            n_resamples=MIN_N_RESAMPLES,
            seed=1,
        )


def test_degenerate_two_observation_sample_no_longer_blessed_as_significant():
    """Regression for a Codex review finding: two constant observations
    per group (e.g. [0,1] vs [0,1]) previously passed straight through and
    could report a spurious `likely_significant=True` result from a
    single resample. This must now be rejected outright as too small."""

    with pytest.raises(InsufficientSampleError):
        two_sample_bootstrap_diff([0.0, 1.0], [0.0, 1.0], n_resamples=1, seed=42)


def test_below_minimum_n_resamples_rejected():
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(
            [1.0] * MIN_N_PER_GROUP,
            [1.0] * MIN_N_PER_GROUP,
            n_resamples=MIN_N_RESAMPLES - 1,
            seed=1,
        )


def test_two_sample_bootstrap_diff_rejects_non_finite_values():
    """Regression for a Codex review finding (2026-07-22, third round):
    a non-finite value in either sample previously silently produced NaN
    point/interval fields instead of a visible error."""

    good = [1.0] * 10
    bad = [1.0] * 9 + [float("nan")]
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(bad, good, MIN_N_RESAMPLES, seed=1)
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(good, bad, MIN_N_RESAMPLES, seed=1)


def test_two_sample_bootstrap_diff_rejects_overflow_to_non_finite_from_finite_inputs():
    """Regression for a Codex review finding (2026-07-22, fourth round):
    every individual value is finite, but the mean/difference of finite
    values can still overflow -- the exact reproduced counterexample, two
    ten-value samples at opposite 1e308 magnitudes, previously returned an
    observed difference of -inf and a CI of [nan, nan] instead of
    raising."""

    high = [1e308] * 10
    low = [-1e308] * 10
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(high, low, MIN_N_RESAMPLES, seed=1)


def test_confidence_out_of_range_rejected():
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff(
            [1.0] * MIN_N_PER_GROUP,
            [1.0] * MIN_N_PER_GROUP,
            n_resamples=MIN_N_RESAMPLES,
            seed=1,
            confidence=1.5,
        )


def test_observed_diff_is_the_actual_difference_not_a_resampled_mean():
    """Regression for a Codex review finding (2026-07-21): the point
    estimate was previously mean(diffs across resamples) -- a RANDOM
    quantity -- rather than the actual observed difference on the real
    data. Constant data makes both quantities identical, so this alone
    would not have caught the bug; the key assertion is that observed_diff
    is deterministic and matches the exact arithmetic difference of means,
    independent of n_resamples/seed (see the next test)."""

    baseline = [1.0] * MIN_N_PER_GROUP
    candidate = [2.0] * MIN_N_PER_GROUP
    result = two_sample_bootstrap_diff(baseline, candidate, n_resamples=MIN_N_RESAMPLES, seed=1)
    assert result.observed_diff == pytest.approx(1.0)  # 2.0 - 1.0, exactly
    assert result.ci_lower == pytest.approx(1.0)
    assert result.ci_upper == pytest.approx(1.0)


def test_observed_diff_is_seed_and_resample_count_invariant():
    """The critical property the bug violated: the OBSERVED difference
    must not depend on the seed or n_resamples -- only the CI bounds
    (uncertainty around it) may."""

    baseline = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    candidate = [4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0]
    expected_diff = (sum(candidate) / len(candidate)) - (sum(baseline) / len(baseline))

    result_a = two_sample_bootstrap_diff(baseline, candidate, n_resamples=100, seed=1)
    result_b = two_sample_bootstrap_diff(baseline, candidate, n_resamples=5000, seed=999)

    assert result_a.observed_diff == pytest.approx(expected_diff)
    assert result_b.observed_diff == pytest.approx(expected_diff)
    assert result_a.observed_diff == result_b.observed_diff


def test_identical_distributions_not_significant():
    values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    result = two_sample_bootstrap_diff(values, values, n_resamples=1000, seed=1)
    assert result.observed_diff == pytest.approx(0.0)
    assert result.likely_significant is False


def test_deterministic_given_same_seed():
    a = two_sample_bootstrap_diff([1.0, 2.0, 3.0] * 4, [4.0, 5.0, 6.0] * 4, n_resamples=200, seed=7)
    b = two_sample_bootstrap_diff([1.0, 2.0, 3.0] * 4, [4.0, 5.0, 6.0] * 4, n_resamples=200, seed=7)
    assert a == b


# --- run() ---------------------------------------------------------------------


def test_missing_column_raises(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_empty_dataset_raises(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(
        columns=[
            "trade_id",
            "symbol",
            "is_long",
            "entry_time",
            "exit_time",
            "entry_price",
            "exit_price",
            "stop_price",
            "profit",
        ]
    ).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(InsufficientSampleError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_duplicate_trade_id_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(
        [
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 102.0,
                "stop_price": 98.0,
                "profit": 10.0,
            },
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 99.0,
                "stop_price": 98.0,
                "profit": -5.0,
            },
        ]
    ).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_symbol_filter_rejects_mismatched_rows(tmp_path):
    """Regression for a Codex review finding: the `symbol` parameter
    previously only labelled metadata and did not validate either input,
    so arbitrary/incomparable datasets could be silently compared."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12, symbol="EURUSD")
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12, symbol="XAUUSD")

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            symbol="XAUUSD",
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_no_symbol_filter_still_rejects_datasets_covering_different_symbols(tmp_path):
    """Regression for a Codex review finding (2026-07-22): with NO
    'symbol' filter supplied at all, the two datasets' own symbol sets
    were never checked against EACH OTHER -- an EURUSD baseline vs. an
    XAUUSD candidate was accepted and compared as if they were the same
    instrument. This must be rejected even when the caller never passes
    'symbol'."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12, symbol="EURUSD")
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12, symbol="XAUUSD")

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )  # no symbol= at all


def test_impossible_chronology_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    rows = []
    for i in range(12):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-22T00:00:00Z",
                "exit_time": "2026-07-21T00:00:00Z",  # entry after exit
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows).to_csv(candidate_path, index=False)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_disjoint_trade_periods_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round):
    only symbol sets were checked -- a same-symbol January-2026 baseline
    vs. January-2025 candidate was still accepted and compared as if the
    two experiments covered the same market period.

    **Corrected, 2026-07-22 Codex review finding (fourth round): the old
    mechanism (checking whether the two datasets' own observed ranges
    overlap) let a baseline spanning Jan 1-31 and a candidate spanning
    Jan 31-Feb 28 pass because the ranges touch at one instant --
    period_start/period_end are now a mandatory, caller-claimed window
    that every trade in BOTH datasets must fall inside. This test now
    proves the 2025 baseline is rejected against a claimed 2026-only
    comparison window, which subsumes the old disjoint-ranges case.**"""

    baseline_path = tmp_path / "baseline.csv"
    rows_2025 = []
    for i in range(12):
        rows_2025.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2025-01-01T00:00:00Z",
                "exit_time": "2025-01-01T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows_2025).to_csv(baseline_path, index=False)

    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)  # 2026-07-21, per _write_trades

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_trade_touching_period_boundary_still_rejected_if_outside(tmp_path):
    """Regression for the exact reproduced counterexample (2026-07-22,
    fourth round): a baseline spanning Jan 1-31 and a candidate spanning
    Jan 31-Feb 28 previously passed the old overlap check because the
    ranges touch at one instant. Claiming a Jan-only comparison period
    must reject the candidate's February trade."""

    baseline_path = tmp_path / "baseline.csv"
    rows = []
    for i in range(12):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-01-01T00:00:00Z",
                "exit_time": "2026-01-01T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows).to_csv(baseline_path, index=False)

    candidate_path = tmp_path / "candidate.csv"
    rows2 = []
    for i in range(12):
        rows2.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-02-27T00:00:00Z",
                "exit_time": "2026-02-27T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows2).to_csv(candidate_path, index=False)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            period_start="2026-01-01T00:00:00Z",
            period_end="2026-01-31T23:59:59Z",
        )


def test_manifest_field_mismatch_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    broker/timeframe/modelling_mode/set_file were a single shared,
    optional, caller-trusted assertion -- not two compared manifests.
    Supplying mismatched baseline/candidate values for the same field
    must now be rejected."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(ValueError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
            baseline_broker="Deriv",
            candidate_broker="IC Markets",
        )


def test_manifest_field_match_accepted(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    summary = run(
        baseline_path,
        candidate_path,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        baseline_broker="Deriv",
        candidate_broker="Deriv",
    )
    assert summary["baseline_broker"] == "Deriv"
    assert summary["candidate_broker"] == "Deriv"


def test_role_preserving_dataset_hashes_differ_by_role(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    the one combined, order-independent dataset hash is not
    role-preserving -- swapping which physical file is baseline vs.
    candidate could retain the same combined hash. Separate per-role
    hashes must differ whenever the two files' content differs."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "compare.json"

    run(
        baseline_path,
        candidate_path,
        output_json=output_json,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        repo_path=REPO_ROOT,
    )
    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert (
        payload["summary"]["baseline_dataset_hash"] != payload["summary"]["candidate_dataset_hash"]
    )


def test_baseline_and_candidate_ea_version_recorded_separately(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round): a
    single shared ea_version/data_source value is insufficient to
    identify TWO releases."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    summary = run(
        baseline_path,
        candidate_path,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        baseline_ea_version="v6.37",
        candidate_ea_version="v8.11",
        baseline_data_source="mt5_export_a",
        candidate_data_source="mt5_export_b",
    )
    assert summary["baseline_ea_version"] == "v6.37"
    assert summary["candidate_ea_version"] == "v8.11"
    assert summary["baseline_data_source"] == "mt5_export_a"
    assert summary["candidate_data_source"] == "mt5_export_b"


def test_naive_timestamp_rejected(tmp_path):
    """Regression for a Codex review finding: this script previously did
    not parse or validate entry/exit timestamps at all."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    rows = []
    for i in range(12):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00",
                "exit_time": "2026-07-21T01:00:00",  # naive
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 10.0,
            }
        )
    pd.DataFrame(rows).to_csv(candidate_path, index=False)

    with pytest.raises(ValueError):
        run(
            baseline_path,
            candidate_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_win_rate_diff_uses_newcombe_wilson_not_bootstrap(tmp_path):
    """Regression for a Codex review finding: bootstrapping raw 0/1
    win-rate outcomes collapses to a degenerate [1.0, 1.0] interval for
    an all-loss-vs-all-win boundary sample. This must now be a real,
    non-degenerate interval via the Newcombe-Wilson method."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 10, [-10.0] * 10)  # 10 losses
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 10, [10.0] * 10)  # 10 wins

    summary = run(
        baseline_path,
        candidate_path,
        n_resamples=2000,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )
    win_rate_diff = summary["win_rate_diff"]
    assert win_rate_diff["method"] == "newcombe_wilson"
    assert win_rate_diff["observed_diff"] == pytest.approx(1.0)
    assert win_rate_diff["ci_upper"] == pytest.approx(1.0)
    assert win_rate_diff["ci_lower"] < win_rate_diff["ci_upper"]  # NOT degenerate


def test_output_path_colliding_with_input_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(
            baseline_path,
            candidate_path,
            output_json=baseline_path,
            period_start=DEFAULT_PERIOD_START,
            period_end=DEFAULT_PERIOD_END,
        )


def test_stark_difference_detected(tmp_path):
    # 20 trades per dataset (well above MIN_N_PER_GROUP) -- large enough
    # for the bootstrap CI to actually resolve a 0.25 vs 0.75 win-rate gap.
    baseline_exits = [95.0] * 15 + [105.0] * 5
    baseline_profits = [-10.0] * 15 + [10.0] * 5
    candidate_exits = [105.0] * 15 + [95.0] * 5
    candidate_profits = [10.0] * 15 + [-10.0] * 5

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, baseline_exits, baseline_profits)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, candidate_exits, candidate_profits)

    summary = run(
        baseline_path,
        candidate_path,
        n_resamples=2000,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
    )

    assert summary["baseline_win_rate"] == pytest.approx(0.25)
    assert summary["candidate_win_rate"] == pytest.approx(0.75)
    assert summary["baseline_expectancy_r"] == pytest.approx(-1.25)
    assert summary["candidate_expectancy_r"] == pytest.approx(1.25)
    assert summary["win_rate_diff"]["observed_diff"] == pytest.approx(
        0.5
    )  # EXACT, not resample-dependent
    assert summary["win_rate_diff"]["likely_significant"] is True


def test_writes_output_json(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "out" / "compare.json"

    run(
        baseline_path,
        candidate_path,
        output_json=output_json,
        n_resamples=100,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        repo_path=REPO_ROOT,
    )

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_baseline_trades"] == 12
    assert payload["summary"]["n_candidate_trades"] == 12
    assert "metadata" in payload


def test_spread_and_slippage_note_persisted(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    spread_note/slippage_note exist on ReportMetadata but no analysis
    caller exposed or populated them -- this module's own docstring
    already claimed the caller could assert cost identity, but no
    parameter existed to do so."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "out" / "compare.json"

    run(
        baseline_path,
        candidate_path,
        output_json=output_json,
        n_resamples=100,
        seed=1,
        period_start=DEFAULT_PERIOD_START,
        period_end=DEFAULT_PERIOD_END,
        spread_note="2-pip fixed spread assumed",
        slippage_note="no slippage modelled",
        repo_path=REPO_ROOT,
    )

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["spread_note"] == "2-pip fixed spread assumed"
    assert payload["metadata"]["slippage_note"] == "no slippage modelled"


def test_cli_main_success(tmp_path, capsys):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    exit_code = main(
        [
            "--baseline-csv",
            str(baseline_path),
            "--candidate-csv",
            str(candidate_path),
            "--n-resamples",
            "100",
            "--period-start",
            DEFAULT_PERIOD_START,
            "--period-end",
            DEFAULT_PERIOD_END,
        ]
    )
    assert exit_code == 0
    assert "baseline_n=12" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(
        [
            "--baseline-csv",
            str(tmp_path / "nope.csv"),
            "--candidate-csv",
            str(tmp_path / "nope2.csv"),
            "--period-start",
            DEFAULT_PERIOD_START,
            "--period-end",
            DEFAULT_PERIOD_END,
        ]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
