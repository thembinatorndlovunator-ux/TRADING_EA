"""Shared pytest fixtures -- synthetic data only, per the reproducibility
contract ("if real evidence data is unavailable, tests use clearly labelled
synthetic fixtures... rather than fabricate results"). No file under
01_BASELINE/ or any real account export is read by any test here."""

from __future__ import annotations

import json

import pytest


def make_valid_record(**overrides) -> dict:
    """A schema-valid TradeDecision dict, matching TRADE_DECISION_SCHEMA.json
    exactly -- NOT necessarily what the current live EA build actually
    produces (see schema.py's docstring on the market_family/intraday_mode
    gap); this is the target shape a fixed EA build should converge to."""

    record = {
        "signal_id": "sig-0001",
        "timestamp_utc": "2026-07-21T14:05:30Z",
        "symbol": "XAUUSD",
        "market_family": "METAL",
        "intraday_mode": "SCALP",
        "regime": "REGIME_TRENDING_UP",
        "regime_confidence": 72.5,
        "direction": "BUY",
        "strategy": "TrendFollowingStrategy",
        "setup": "TrendlinePullback",
        "candlestick_pattern": "BullishEngulfing",
        "chart_pattern": None,
        "score": 68.0,
        "score_breakdown": {"base": 68.0},
        "entry": 2350.55,
        "stop": 2345.10,
        "targets": [2361.45],
        "risk_percent": 0.3,
        "news_state": "clear",
        "session_state": "london",
        "reasons_passed": ["daily_weekly_loss_caps_clear"],
        "reasons_rejected": [],
        "ea_version": "1.01-task027-order-submission-optional",
        "git_commit": "ddcee10",
    }
    record.update(overrides)
    return record


def make_current_ea_record(**overrides) -> dict:
    """A record shaped exactly like what ThembaAdaptiveIntradayEA.mq5
    ACTUALLY emits today: signal_id, market_family, and intraday_mode all
    empty strings (the confirmed, documented cross-layer gap) -- used to
    prove the schema genuinely catches this, rather than silently passing
    it."""

    record = make_valid_record(signal_id="", market_family="", intraday_mode="")
    record.update(overrides)
    return record


@pytest.fixture
def valid_record() -> dict:
    return make_valid_record()


@pytest.fixture
def current_ea_record() -> dict:
    return make_current_ea_record()


@pytest.fixture
def journal_dir_factory(tmp_path):
    """Returns a function that writes a decisions_YYYYMMDD.jsonl file with
    the given list of already-JSON-serializable dict/str lines, and returns
    the containing directory."""

    def _write(filename: str, lines: list) -> "Path":  # noqa: F821
        path = tmp_path / filename
        with path.open("w", encoding="utf-8") as fh:
            for line in lines:
                if isinstance(line, str):
                    fh.write(line + "\n")
                else:
                    fh.write(json.dumps(line) + "\n")
        return tmp_path

    return _write
