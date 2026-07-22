from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from analysis.analyse_baseline import main, run
from analysis.csv_io import CsvSchemaError
from analysis.metrics import InsufficientSampleError

REPO_ROOT = Path(__file__).resolve().parents[3]


def _write_trades(path: Path, rows: list[dict] | None = None) -> None:
    pd.DataFrame(
        rows
        or [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 102.0,
                "stop_price": 98.0,
                "profit": 40.0,
            },
            {
                "trade_id": "t2",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T02:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "exit_price": 99.0,
                "stop_price": 98.0,
                "profit": -20.0,
            },
            {
                "trade_id": "t3",
                "symbol": "XAUUSD",
                "is_long": "False",
                "entry_time": "2026-07-21T04:00:00Z",
                "exit_time": "2026-07-21T05:00:00Z",
                "entry_price": 100.0,
                "exit_price": 95.0,
                "stop_price": 102.0,
                "profit": 50.0,
            },
            {
                "trade_id": "t4",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T06:00:00Z",
                "exit_time": "2026-07-21T07:00:00Z",
                "entry_price": 100.0,
                "exit_price": 98.0,
                "stop_price": 98.0,
                "profit": -20.0,
            },
        ]
    ).to_csv(path, index=False)


def test_n_resamples_and_confidence_exposed_and_actually_used(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    compute_trade_summary previously exposed 'seed' but hard-wired every
    win_rate()/expectancy() call to their own default n_resamples/
    confidence (2000/0.95), regardless of what a caller passed to run()
    -- these are now genuinely threaded through and persisted."""

    path = tmp_path / "trades.csv"
    _write_trades(path)

    summary = run(path, n_resamples=150, confidence=0.90)
    assert summary["expectancy_dollars"]["n_resamples"] == 150
    assert summary["expectancy_dollars"]["confidence"] == 0.90
    assert summary["expectancy_r"]["n_resamples"] == 150
    assert summary["expectancy_r"]["confidence"] == 0.90
    assert summary["win_rate"]["confidence"] == 0.90


def test_leading_zero_trade_id_not_collapsed_by_numeric_inference(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round):
    'trade_id' was previously read via plain pandas type inference -- a
    CSV containing IDs "001" and "1" loaded as integer values 1, 1 and
    was rejected as a false duplicate."""

    path = tmp_path / "trades.csv"
    _write_trades(
        path,
        [
            {
                "trade_id": "001",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 102.0,
                "stop_price": 98.0,
                "profit": 40.0,
            },
            {
                "trade_id": "1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T02:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "exit_price": 99.0,
                "stop_price": 98.0,
                "profit": -20.0,
            },
        ],
    )

    summary = run(path)
    assert summary["n_trades"] == 2


def test_missing_column_raises(tmp_path):
    path = tmp_path / "trades.csv"
    pd.DataFrame({"trade_id": ["t1"]}).to_csv(path, index=False)
    with pytest.raises(CsvSchemaError):
        run(path)


def test_empty_trades_raises(tmp_path):
    path = tmp_path / "trades.csv"
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
    ).to_csv(path, index=False)
    with pytest.raises(InsufficientSampleError):
        run(path)


def test_non_positive_starting_balance_rejected(tmp_path):
    """Regression for a Codex review finding: a non-positive starting
    balance made percentage drawdown silently meaningless (0.0 default)."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(InsufficientSampleError):
        run(path, starting_balance=0.0)
    with pytest.raises(InsufficientSampleError):
        run(path, starting_balance=-500.0)


def test_non_finite_starting_balance_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22):
    `starting_balance <= 0` is False for NaN (every comparison against
    NaN is False in Python), so a NaN starting_balance previously slipped
    past that check and produced a NaN final balance with a plausible-
    looking 0.0 drawdown in memory instead of a visible error."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(InsufficientSampleError):
        run(path, starting_balance=float("nan"))


def test_naive_timestamp_rejected(tmp_path):
    """Regression for a Codex review finding: this script previously
    called pd.to_datetime(utc=True), which silently treats a naive string
    (no "Z"/offset) as if it were already UTC."""

    path = tmp_path / "trades.csv"
    rows = [
        {
            "trade_id": "t1",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": "2026-07-21T00:00:00",
            "exit_time": "2026-07-21T01:00:00",  # naive
            "entry_price": 100.0,
            "exit_price": 102.0,
            "stop_price": 98.0,
            "profit": 40.0,
        }
    ]
    _write_trades(path, rows)
    with pytest.raises(ValueError):
        run(path)


def test_impossible_chronology_rejected(tmp_path):
    """Regression for a Codex review finding (2026-07-22, third round): a
    trade whose entry_time is AFTER its exit_time was previously accepted
    and reported as one valid trade."""

    path = tmp_path / "trades.csv"
    rows = [
        {
            "trade_id": "t1",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": "2026-07-22T00:00:00Z",
            "exit_time": "2026-07-21T00:00:00Z",  # entry after exit
            "entry_price": 100.0,
            "exit_price": 102.0,
            "stop_price": 98.0,
            "profit": 40.0,
        }
    ]
    _write_trades(path, rows)
    with pytest.raises(CsvSchemaError):
        run(path)


def test_malformed_stop_geometry_rejected(tmp_path):
    """Regression for a Codex review finding: compute_r_multiple's live
    fail-safe silently returns 0R for malformed stop geometry -- a long
    trade with entry 100 and stop 101 must be rejected as malformed
    input, not reported as a plausible 0R trade."""

    path = tmp_path / "trades.csv"
    rows = [
        {
            "trade_id": "t1",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": "2026-07-21T00:00:00Z",
            "exit_time": "2026-07-21T01:00:00Z",
            "entry_price": 100.0,
            "exit_price": 102.0,
            "stop_price": 101.0,  # stop on wrong side
            "profit": 40.0,
        }
    ]
    _write_trades(path, rows)
    with pytest.raises(CsvSchemaError):
        run(path)


def test_same_timestamp_trades_give_deterministic_drawdown(tmp_path):
    """Regression for a Codex review finding (2026-07-22): sorting only
    by exit_time leaves same-instant trades in an arbitrary tie-break
    order (CSV row order); reversing two same-time win/loss rows
    previously changed the observed max drawdown from 10.0% to ~9.09%
    with identical timestamps and net P/L. Same-instant P/L is now
    summed into one balance step before computing drawdown, so the
    result must be identical regardless of row order."""

    same_time = "2026-07-21T00:00:00Z"
    win_then_loss = [
        {
            "trade_id": "a",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": same_time,
            "exit_time": same_time,
            "entry_price": 100.0,
            "exit_price": 110.0,
            "stop_price": 98.0,
            "profit": 100.0,
        },
        {
            "trade_id": "b",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": same_time,
            "exit_time": same_time,
            "entry_price": 100.0,
            "exit_price": 90.0,
            "stop_price": 98.0,
            "profit": -50.0,
        },
    ]
    loss_then_win = list(reversed(win_then_loss))

    path_a = tmp_path / "a.csv"
    _write_trades(path_a, win_then_loss)
    path_b = tmp_path / "b.csv"
    _write_trades(path_b, loss_then_win)

    summary_a = run(path_a, starting_balance=1000.0)
    summary_b = run(path_b, starting_balance=1000.0)

    assert summary_a["max_balance_drawdown_abs"] == summary_b["max_balance_drawdown_abs"]
    assert summary_a["max_balance_drawdown_pct"] == summary_b["max_balance_drawdown_pct"]
    assert summary_a["final_balance"] == summary_b["final_balance"] == pytest.approx(1050.0)


def test_same_timestamp_trades_give_deterministic_losing_streak(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    longest_losing_streak previously iterated 'profits' in trades_sorted's
    own row order, which is ARBITRARY among same-instant trades (the same
    tie-break problem drawdown above already solves). Reordering three
    simultaneous outcomes (loss/win/loss vs. loss/loss/win, net -40 at
    that one instant) previously changed the reported streak from 1 to 2.
    The streak is now computed over one order-independent balance STEP
    per distinct exit_time (net -40, a single loss step), so it must be
    identical regardless of row order."""

    same_time = "2026-07-21T00:00:00Z"
    loss_win_loss = [
        {
            "trade_id": "a",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": same_time,
            "exit_time": same_time,
            "entry_price": 100.0,
            "exit_price": 85.0,
            "stop_price": 98.0,
            "profit": -30.0,
        },
        {
            "trade_id": "b",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": same_time,
            "exit_time": same_time,
            "entry_price": 100.0,
            "exit_price": 110.0,
            "stop_price": 98.0,
            "profit": 20.0,
        },
        {
            "trade_id": "c",
            "symbol": "XAUUSD",
            "is_long": "True",
            "entry_time": same_time,
            "exit_time": same_time,
            "entry_price": 100.0,
            "exit_price": 85.0,
            "stop_price": 98.0,
            "profit": -30.0,
        },
    ]
    loss_loss_win = [loss_win_loss[0], loss_win_loss[2], loss_win_loss[1]]

    path_a = tmp_path / "a.csv"
    _write_trades(path_a, loss_win_loss)
    path_b = tmp_path / "b.csv"
    _write_trades(path_b, loss_loss_win)

    summary_a = run(path_a, starting_balance=1000.0)
    summary_b = run(path_b, starting_balance=1000.0)

    assert summary_a["longest_losing_streak"] == summary_b["longest_losing_streak"] == 1


def test_trades_per_day_uses_authenticated_evaluation_period_when_given(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    trades_per_day previously ALWAYS divided by the active trade envelope
    (earliest entry to latest exit) -- 4 trades spanning 7 active hours
    were blessed as ~13.7/day even if they actually came from a
    month-long run. A caller who knows the real evaluation window can now
    supply it explicitly, overriding the active-envelope denominator."""

    path = tmp_path / "trades.csv"
    _write_trades(path)  # default fixture: 4 trades spanning 7 active hours

    summary_default = run(path, starting_balance=1000.0)
    assert summary_default["trades_per_day_denominator_source"] == "active_trade_envelope"
    assert summary_default["trades_per_day"] == pytest.approx(4 / (7.0 / 24.0))

    summary_authenticated = run(path, starting_balance=1000.0, evaluation_period_days=30.0)
    assert (
        summary_authenticated["trades_per_day_denominator_source"]
        == "authenticated_evaluation_period"
    )
    assert summary_authenticated["trades_per_day_denominator_days"] == pytest.approx(30.0)
    assert summary_authenticated["trades_per_day"] == pytest.approx(4 / 30.0)


def test_evaluation_period_days_rejects_non_positive(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(ValueError):
        run(path, evaluation_period_days=0.0)
    with pytest.raises(ValueError):
        run(path, evaluation_period_days=-5.0)


def test_avg_winner_loser_duration_report_sample_sizes(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    average winner, average loser, and duration carried neither subgroup
    sample sizes nor uncertainty, despite the task's sample-size/
    uncertainty contract."""

    path = tmp_path / "trades.csv"
    _write_trades(path)  # default fixture: 2 winners, 2 losers, 4 trades total
    summary = run(path, starting_balance=1000.0)
    assert summary["avg_winner_dollars_n"] == 2
    assert summary["avg_loser_dollars_n"] == 2
    assert summary["avg_trade_duration_minutes_n"] == 4


def test_duplicate_trade_id_rejected(tmp_path):
    """Regression for a Codex review finding: duplicate trade_id values
    were never checked, silently double-counting a trade."""

    path = tmp_path / "trades.csv"
    _write_trades(
        path,
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
                "profit": 40.0,
            },
            {
                "trade_id": "dup",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T02:00:00Z",
                "exit_time": "2026-07-21T03:00:00Z",
                "entry_price": 100.0,
                "exit_price": 99.0,
                "stop_price": 98.0,
                "profit": -20.0,
            },
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(path)


def test_non_finite_value_rejected(tmp_path):
    """Regression for a Codex review finding: NaN/non-numeric values in
    numeric columns were never checked before being fed into arithmetic."""

    path = tmp_path / "trades.csv"
    _write_trades(
        path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 102.0,
                "stop_price": 98.0,
                "profit": float("nan"),
            },
        ],
    )
    with pytest.raises(CsvSchemaError):
        run(path)


def test_output_path_colliding_with_input_rejected(tmp_path):
    """Regression for a Codex review finding: an output path equal to the
    input path would overwrite the source before/while reading it."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    with pytest.raises(CsvSchemaError):
        run(path, output_json=path)


def test_summary_hand_computed(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)

    summary = run(path, starting_balance=1000.0)

    assert summary["n_trades"] == 4
    assert summary["win_rate"]["value"] == pytest.approx(0.5)
    assert summary["win_rate"]["n"] == 4
    assert summary["expectancy_dollars"]["value"] == pytest.approx(12.5)
    assert summary["expectancy_r"]["value"] == pytest.approx(0.5)
    assert summary["profit_factor"] == pytest.approx(2.25)  # 90 / 40
    assert summary["gross_profit"] == pytest.approx(90.0)
    assert summary["gross_loss"] == pytest.approx(-40.0)

    # balance_curve = [1000, 1040, 1020, 1070, 1050]
    # largest abs/pct decline both at peak=1040(idx1) -> trough=1020(idx2): 20, ~1.923%
    assert summary["max_balance_drawdown_abs"] == pytest.approx(20.0)
    assert summary["max_balance_drawdown_pct"] == pytest.approx(20.0 / 1040.0)
    assert summary["final_balance"] == pytest.approx(1050.0)
    assert summary["max_equity_drawdown"] is None


def test_baseline_comparison_metrics_hand_computed(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fourth round):
    TEST_PLAN.md's minimum baseline-comparison surface (recovery factor,
    equity-peak giveback, longest losing streak, average winner/loser,
    duration, trades/day) was computable from this schema but never
    reported by any pipeline."""

    path = tmp_path / "trades.csv"
    _write_trades(path)

    summary = run(path, starting_balance=1000.0)

    # balance_curve = [1000, 1040, 1020, 1070, 1050]; net_profit=50,
    # max_drawdown_abs=20 -> recovery_factor=2.5.
    assert summary["net_profit"] == pytest.approx(50.0)
    assert summary["recovery_factor"] == pytest.approx(2.5)

    # Sorted-by-exit-time profits: [40, -20, 50, -20] -- each loss is
    # isolated (win in between) -> longest losing streak = 1.
    assert summary["longest_losing_streak"] == 1

    # winners=[40,50] -> avg 45.0; losers=[-20,-20] -> avg -20.0.
    assert summary["avg_winner_dollars"] == pytest.approx(45.0)
    assert summary["avg_loser_dollars"] == pytest.approx(-20.0)

    # Every fixture trade is exactly 60 minutes (entry to exit).
    assert summary["avg_trade_duration_minutes"] == pytest.approx(60.0)

    # Period spans 7 hours (00:00 to 07:00) = 7/24 days; 4 trades.
    assert summary["trades_per_day"] == pytest.approx(4 / (7.0 / 24.0))

    # Balance-peak giveback (default arm=1.0%, floor=0.5%) -- renamed from
    # "equity_peak_giveback" (Codex review finding, 2026-07-22, fifth
    # round: this is a balance-based proxy, not the master-prompt equity
    # metric) -- hand-traced against the same [1000, 1040, 1020, 1070,
    # 1050] balance curve: arms at index 1 (4% >= 1%), triggers at index 2
    # (1.923% giveback from peak 1040), recovers at the new peak
    # (index 3), triggers again at index 4 (1.869% giveback from peak
    # 1070).
    giveback = summary["balance_peak_giveback"]
    assert giveback["armed"] is True
    assert giveback["n_trigger_events"] == 2
    assert giveback["trigger_indices"] == [2, 4]
    assert giveback["max_giveback_pct"] == pytest.approx(20.0 / 1040.0)
    assert giveback["max_giveback_pct_index"] == 2


def test_r_multiples_hand_computed_per_trade(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    per_trade_csv = tmp_path / "out" / "per_trade.csv"

    run(path, per_trade_csv=per_trade_csv)

    df = pd.read_csv(per_trade_csv).set_index("trade_id")
    assert df.loc["t1", "r_multiple"] == pytest.approx(1.0)
    assert df.loc["t2", "r_multiple"] == pytest.approx(-0.5)
    assert df.loc["t3", "r_multiple"] == pytest.approx(2.5)
    assert df.loc["t4", "r_multiple"] == pytest.approx(-1.0)


def test_output_json_auto_derived_when_per_trade_csv_given_without_it(tmp_path):
    """Regression for a Codex review finding (2026-07-22, sixth round): a
    caller requesting per_trade_csv without output_json previously got a
    CSV with NO accompanying provenance metadata anywhere -- this
    pipeline's summary/metadata lives entirely in output_json. An
    implicit path is now derived from per_trade_csv."""

    path = tmp_path / "trades.csv"
    _write_trades(path)
    per_trade_csv = tmp_path / "out" / "per_trade.csv"

    run(path, per_trade_csv=per_trade_csv)

    derived_output_json = tmp_path / "out" / "per_trade.summary.json"
    assert derived_output_json.exists()
    payload = json.loads(derived_output_json.read_text(encoding="utf-8"))
    assert payload["metadata"]["dataset_hash"]


def test_writes_output_json_with_metadata(tmp_path):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    output_json = tmp_path / "out" / "summary.json"

    run(path, output_json=output_json, symbol="XAUUSD", broker="Deriv", seed=1, repo_path=REPO_ROOT)

    payload = json.loads(output_json.read_text(encoding="utf-8"))
    assert payload["summary"]["n_trades"] == 4
    assert payload["metadata"]["symbol"] == "XAUUSD"
    assert payload["metadata"]["broker"] == "Deriv"


def test_dataset_hash_reflects_actual_file_parsed_not_a_later_reread(tmp_path):
    """Regression for a Codex review finding (2026-07-22, fifth round):
    trades_csv was previously parsed once, then SEPARATELY re-read and
    hashed by build_report_metadata() much later in run() -- a mutation
    landing in that gap (after parsing, before hashing) produced a
    persisted summary computed from the OLD content while dataset_hash
    described the NEW file, an ABA-style desync. read_csv_with_required_
    columns_and_hash reads the file exactly once and derives both the
    parsed DataFrame and the hash from that same byte buffer, so the two
    can never disagree. Proven here: two distinct byte states of the same
    path must produce two distinct hashes, each reflecting that specific
    run()'s own summary."""

    path = tmp_path / "trades.csv"
    _write_trades(path)  # default fixture: net_profit = 40-20+50-20 = 50
    output_json_a = tmp_path / "out_a" / "summary.json"
    run(path, output_json=output_json_a, repo_path=REPO_ROOT)
    payload_a = json.loads(output_json_a.read_text(encoding="utf-8"))

    _write_trades(
        path,
        [
            {
                "trade_id": "t1",
                "symbol": "XAUUSD",
                "is_long": "True",
                "entry_time": "2026-07-21T00:00:00Z",
                "exit_time": "2026-07-21T01:00:00Z",
                "entry_price": 100.0,
                "exit_price": 105.0,
                "stop_price": 98.0,
                "profit": 999.0,
            }
        ],
    )
    output_json_b = tmp_path / "out_b" / "summary.json"
    run(path, output_json=output_json_b, repo_path=REPO_ROOT)
    payload_b = json.loads(output_json_b.read_text(encoding="utf-8"))

    assert payload_a["metadata"]["dataset_hash"] != payload_b["metadata"]["dataset_hash"]
    assert payload_a["summary"]["net_profit"] == pytest.approx(50.0)
    assert payload_b["summary"]["net_profit"] == pytest.approx(999.0)


def test_cli_main_success(tmp_path, capsys):
    path = tmp_path / "trades.csv"
    _write_trades(path)
    exit_code = main(["--trades-csv", str(path)])
    assert exit_code == 0
    assert "n=4" in capsys.readouterr().out


def test_cli_main_missing_file(tmp_path, capsys):
    exit_code = main(["--trades-csv", str(tmp_path / "nope.csv")])
    assert exit_code == 1
    assert "ERROR" in capsys.readouterr().err
