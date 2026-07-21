from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.compare_releases import MIN_N_PER_GROUP, MIN_N_RESAMPLES, main, run, two_sample_bootstrap_diff
from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_trades(path: Path, exits: list[float], profits: list[float], symbol: str = "XAUUSD") -> None:
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
        two_sample_bootstrap_diff([1.0] * (MIN_N_PER_GROUP - 1), [1.0] * MIN_N_PER_GROUP,
                                    n_resamples=MIN_N_RESAMPLES, seed=1)


def test_degenerate_two_observation_sample_no_longer_blessed_as_significant():
    """Regression for a Codex review finding: two constant observations
    per group (e.g. [0,1] vs [0,1]) previously passed straight through and
    could report a spurious `likely_significant=True` result from a
    single resample. This must now be rejected outright as too small."""

    with pytest.raises(InsufficientSampleError):
        two_sample_bootstrap_diff([0.0, 1.0], [0.0, 1.0], n_resamples=1, seed=42)


def test_below_minimum_n_resamples_rejected():
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff([1.0] * MIN_N_PER_GROUP, [1.0] * MIN_N_PER_GROUP,
                                    n_resamples=MIN_N_RESAMPLES - 1, seed=1)


def test_confidence_out_of_range_rejected():
    with pytest.raises(ValueError):
        two_sample_bootstrap_diff([1.0] * MIN_N_PER_GROUP, [1.0] * MIN_N_PER_GROUP,
                                    n_resamples=MIN_N_RESAMPLES, seed=1, confidence=1.5)


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
        run(baseline_path, candidate_path)


def test_empty_dataset_raises(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(
        columns=["trade_id", "symbol", "is_long", "entry_time", "exit_time",
                  "entry_price", "exit_price", "stop_price", "profit"]
    ).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(InsufficientSampleError):
        run(baseline_path, candidate_path)


def test_duplicate_trade_id_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(
        [
            {"trade_id": "dup", "symbol": "XAUUSD", "is_long": "True",
             "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T01:00:00Z",
             "entry_price": 100.0, "exit_price": 102.0, "stop_price": 98.0, "profit": 10.0},
            {"trade_id": "dup", "symbol": "XAUUSD", "is_long": "True",
             "entry_time": "2026-07-21T00:00:00Z", "exit_time": "2026-07-21T01:00:00Z",
             "entry_price": 100.0, "exit_price": 99.0, "stop_price": 98.0, "profit": -5.0},
        ]
    ).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(baseline_path, candidate_path)


def test_symbol_filter_rejects_mismatched_rows(tmp_path):
    """Regression for a Codex review finding: the `symbol` parameter
    previously only labelled metadata and did not validate either input,
    so arbitrary/incomparable datasets could be silently compared."""

    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12, symbol="EURUSD")
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12, symbol="XAUUSD")

    with pytest.raises(CsvSchemaError):
        run(baseline_path, candidate_path, symbol="XAUUSD")


def test_output_path_colliding_with_input_rejected(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [105.0] * 12, [10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    with pytest.raises(CsvSchemaError):
        run(baseline_path, candidate_path, output_json=baseline_path)


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

    summary = run(baseline_path, candidate_path, n_resamples=2000, seed=1)

    assert summary["baseline_win_rate"] == pytest.approx(0.25)
    assert summary["candidate_win_rate"] == pytest.approx(0.75)
    assert summary["baseline_expectancy_r"] == pytest.approx(-1.25)
    assert summary["candidate_expectancy_r"] == pytest.approx(1.25)
    assert summary["win_rate_diff"]["observed_diff"] == pytest.approx(0.5)  # EXACT, not resample-dependent
    assert summary["win_rate_diff"]["likely_significant"] is True


def test_writes_output_json(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)
    output_json = tmp_path / "out" / "compare.json"

    run(baseline_path, candidate_path, output_json=output_json, n_resamples=100, seed=1, repo_path=REPO_ROOT)

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_baseline_trades"] == 12
    assert payload["summary"]["n_candidate_trades"] == 12
    assert "metadata" in payload


def test_cli_main_success(tmp_path, capsys):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0] * 12, [-10.0] * 12)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0] * 12, [10.0] * 12)

    exit_code = main(
        ["--baseline-csv", str(baseline_path), "--candidate-csv", str(candidate_path), "--n-resamples", "100"]
    )
    assert exit_code == 0
    assert "baseline_n=12" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(
        ["--baseline-csv", str(tmp_path / "nope.csv"), "--candidate-csv", str(tmp_path / "nope2.csv")]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
