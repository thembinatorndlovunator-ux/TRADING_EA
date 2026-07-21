from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.compare_releases import main, run, two_sample_bootstrap_diff
from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_trades(path: Path, exits: list[float], profits: list[float]) -> None:
    rows = []
    for i, (exit_price, profit) in enumerate(zip(exits, profits)):
        rows.append(
            {
                "trade_id": f"t{i}",
                "symbol": "XAUUSD",
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


def test_two_sample_bootstrap_diff_insufficient_sample_raises():
    with pytest.raises(InsufficientSampleError):
        two_sample_bootstrap_diff([1.0], [1.0, 2.0], n_resamples=10, seed=1)


def test_two_sample_bootstrap_diff_zero_variance_is_exact():
    result = two_sample_bootstrap_diff([1.0, 1.0], [2.0, 2.0], n_resamples=50, seed=1)
    assert result.diff_mean == pytest.approx(1.0)
    assert result.ci_lower == pytest.approx(1.0)
    assert result.ci_upper == pytest.approx(1.0)
    assert result.likely_significant is True  # CI is [1.0, 1.0], excludes 0


def test_two_sample_bootstrap_diff_identical_samples_not_significant():
    result = two_sample_bootstrap_diff([1.0, 2.0, 3.0], [1.0, 2.0, 3.0], n_resamples=500, seed=1)
    assert result.diff_mean == pytest.approx(0.0, abs=0.5)
    assert result.likely_significant is False


def test_two_sample_bootstrap_diff_deterministic_given_same_seed():
    a = two_sample_bootstrap_diff([1.0, 2.0, 3.0], [4.0, 5.0, 6.0], n_resamples=200, seed=7)
    b = two_sample_bootstrap_diff([1.0, 2.0, 3.0], [4.0, 5.0, 6.0], n_resamples=200, seed=7)
    assert a == b


# --- run() ---------------------------------------------------------------------


def test_missing_column_raises(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0, 105.0], [10.0, 10.0])

    with pytest.raises(CsvSchemaError):
        run(baseline_path, candidate_path)


def test_empty_dataset_raises(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    pd.DataFrame(
        columns=["trade_id", "symbol", "is_long", "entry_time", "exit_time",
                  "entry_price", "exit_price", "stop_price", "profit"]
    ).to_csv(baseline_path, index=False)
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0, 105.0], [10.0, 10.0])

    with pytest.raises(InsufficientSampleError):
        run(baseline_path, candidate_path)


def test_stark_difference_detected(tmp_path):
    # 20 trades per dataset (not 4) -- large enough for the bootstrap CI to
    # actually resolve a 0.25 vs 0.75 win-rate gap; a 4-trade-per-group
    # version of this same test was tried first and correctly did NOT
    # reach significance, which is the reproducibility contract's own
    # "tiny samples cannot drive automatic changes" principle working as
    # intended, not a bug -- this test uses a large enough n specifically
    # to exercise the "genuinely detects a real difference" path instead.
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
    assert summary["win_rate_diff"]["diff_mean"] == pytest.approx(0.5, abs=0.1)
    assert summary["win_rate_diff"]["likely_significant"] is True


def test_writes_output_json(tmp_path):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0, 95.0], [-10.0, -10.0])
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0, 105.0], [10.0, 10.0])
    output_json = tmp_path / "out" / "compare.json"

    run(baseline_path, candidate_path, output_json=output_json, n_resamples=100, seed=1, repo_path=REPO_ROOT)

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_baseline_trades"] == 2
    assert payload["summary"]["n_candidate_trades"] == 2
    assert "metadata" in payload


def test_cli_main_success(tmp_path, capsys):
    baseline_path = tmp_path / "baseline.csv"
    _write_trades(baseline_path, [95.0, 95.0], [-10.0, -10.0])
    candidate_path = tmp_path / "candidate.csv"
    _write_trades(candidate_path, [105.0, 105.0], [10.0, 10.0])

    exit_code = main(
        ["--baseline-csv", str(baseline_path), "--candidate-csv", str(candidate_path), "--n-resamples", "100"]
    )
    assert exit_code == 0
    assert "baseline_n=2" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(
        ["--baseline-csv", str(tmp_path / "nope.csv"), "--candidate-csv", str(tmp_path / "nope2.csv")]
    )
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
