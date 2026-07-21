from __future__ import annotations

import pytest

from analysis.regime_validation import Regime, build_confusion_matrix, classify

# Shared trend-friendly closes: ER = |104-100| / (1+1+1+1) = 4/4 = 1.0
# (passes efficiency for any min_efficiency <= 1.0), index 0 = newest.
TREND_CLOSES = [104.0, 103.0, 102.0, 101.0, 100.0]

# Shared choppy closes: ER = |100-100| / (1+1+1+1) = 0.0 (fails efficiency
# for any min_efficiency > 0).
CHOPPY_CLOSES = [100.0, 101.0, 100.0, 101.0, 100.0]

COMMON_KWARGS = dict(
    efficiency_window=4,
    trend_threshold=0.6,
    expansion_threshold=0.75,
    compression_threshold=0.25,
    min_efficiency=0.3,
    trend_slope_atr_divisor=0.5,
)


def test_invalid_efficiency_window_out_of_range():
    result = classify(
        TREND_CLOSES,
        [0.0, 1.0],
        1.0,
        100.0,
        100.0,
        50.0,
        efficiency_window=10,
        trend_threshold=0.6,
        expansion_threshold=0.75,
        compression_threshold=0.25,
        min_efficiency=0.3,
        trend_slope_atr_divisor=0.5,
        swing_agreement=0.0,
        direction_agree=False,
    )
    assert result.valid is False


def test_invalid_insufficient_atr_history():
    result = classify(
        TREND_CLOSES,
        [1.0],
        1.0,
        100.0,
        100.0,
        50.0,
        **COMMON_KWARGS,
        swing_agreement=0.0,
        direction_agree=False,
    )
    assert result.valid is False


def test_invalid_non_positive_current_atr():
    result = classify(
        TREND_CLOSES,
        [0.0, 1.0, 1.0],
        0.0,
        100.0,
        100.0,
        50.0,
        **COMMON_KWARGS,
        swing_agreement=0.0,
        direction_agree=False,
    )
    assert result.valid is False


def test_ranging_via_efficiency_failure():
    result = classify(
        CHOPPY_CLOSES,
        [0.0, 0.5, 0.5],
        1.0,
        100.0,
        100.0,
        50.0,
        **COMMON_KWARGS,
        swing_agreement=0.0,
        direction_agree=False,
    )
    assert result.valid is True
    assert result.regime == Regime.RANGING
    assert result.ER == pytest.approx(0.0)
    assert result.confidence == pytest.approx(1.0)


def test_trending_up():
    # E kept low (comparisons much larger than current_atr) so the
    # expansion branch never fires; T_final reaches 1.0 (fully clamped).
    result = classify(
        TREND_CLOSES,
        [0.0, 2.0, 2.0],
        1.0,
        ema_now=105.0,
        ema_prior=100.0,
        adx_now=50.0,
        **COMMON_KWARGS,
        swing_agreement=1.0,
        direction_agree=True,
    )
    assert result.regime == Regime.TRENDING_UP
    assert result.T_final == pytest.approx(1.0)
    assert result.confidence == pytest.approx(1.0)


def test_trending_down():
    result = classify(
        TREND_CLOSES,
        [0.0, 2.0, 2.0],
        1.0,
        ema_now=95.0,
        ema_prior=100.0,
        adx_now=50.0,
        **COMMON_KWARGS,
        swing_agreement=1.0,
        direction_agree=True,
    )
    assert result.regime == Regime.TRENDING_DOWN
    assert result.confidence == pytest.approx(1.0)


def test_volatility_expansion_up():
    # E forced high (comparisons much smaller than current_atr).
    result = classify(
        TREND_CLOSES,
        [0.0, 1.0, 1.0],
        2.0,
        ema_now=105.0,
        ema_prior=100.0,
        adx_now=50.0,
        **COMMON_KWARGS,
        swing_agreement=1.0,
        direction_agree=True,
    )
    assert result.regime == Regime.VOLATILITY_EXPANSION_UP
    assert result.E == pytest.approx(1.0)
    assert result.confidence == pytest.approx(1.0)


def test_volatility_expansion_down():
    result = classify(
        TREND_CLOSES,
        [0.0, 1.0, 1.0],
        2.0,
        ema_now=95.0,
        ema_prior=100.0,
        adx_now=50.0,
        **COMMON_KWARGS,
        swing_agreement=1.0,
        direction_agree=True,
    )
    assert result.regime == Regime.VOLATILITY_EXPANSION_DOWN


def test_transition_when_expansion_but_direction_disagrees():
    result = classify(
        TREND_CLOSES,
        [0.0, 1.0, 1.0],
        2.0,
        ema_now=105.0,
        ema_prior=100.0,
        adx_now=50.0,
        **COMMON_KWARGS,
        swing_agreement=0.0,
        direction_agree=False,
    )
    assert result.regime == Regime.TRANSITION_OR_UNCERTAIN
    assert result.confidence == 0.0


def test_compression():
    # T_final forced to 0 (ema_now == ema_prior, swing_agreement 0), E
    # forced low (comparisons much larger than current_atr).
    result = classify(
        TREND_CLOSES,
        [0.0, 5.0, 5.0],
        1.0,
        ema_now=100.0,
        ema_prior=100.0,
        adx_now=50.0,
        **COMMON_KWARGS,
        swing_agreement=0.0,
        direction_agree=False,
    )
    assert result.regime == Regime.COMPRESSION
    assert result.E == pytest.approx(0.0)
    assert result.confidence == pytest.approx(1.0)


def test_ranging_via_middle_zone_fallback():
    # ER passes efficiency (TREND_CLOSES), E in the middle zone (0.5, not
    # compression nor expansion), T_final forced to 0 -- reaches the final
    # "else" RANGING branch, NOT the efficiency-failure branch (ER != 0
    # here, proving this is a genuinely different code path).
    result = classify(
        TREND_CLOSES,
        [0.0, 0.5, 2.0],
        1.0,
        ema_now=100.0,
        ema_prior=100.0,
        adx_now=50.0,
        **COMMON_KWARGS,
        swing_agreement=0.0,
        direction_agree=False,
    )
    assert result.regime == Regime.RANGING
    assert result.ER == pytest.approx(1.0)  # confirms NOT the efficiency-failure path
    assert result.E == pytest.approx(0.5)
    assert result.confidence == pytest.approx(1.0)


# --- build_confusion_matrix -----------------------------------------------------


def test_build_confusion_matrix_mismatched_length_raises():
    with pytest.raises(ValueError):
        build_confusion_matrix(["A", "B"], ["A"])


def test_build_confusion_matrix_empty_raises():
    with pytest.raises(ValueError):
        build_confusion_matrix([], [])


def test_build_confusion_matrix_hand_computed():
    predicted = ["A", "A", "B", "B", "A"]
    actual = ["A", "B", "B", "B", "A"]
    matrix = build_confusion_matrix(predicted, actual)

    assert matrix.loc["A", "A"] == 2  # both predicted A, correctly
    assert matrix.loc["B", "B"] == 2  # both predicted B, correctly
    assert matrix.loc["B", "A"] == 1  # actual B, predicted A (one miss)
