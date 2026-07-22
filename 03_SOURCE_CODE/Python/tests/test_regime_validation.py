from __future__ import annotations

import pytest

from analysis.regime_validation import (
    Regime,
    RegimeTransitionHistory,
    apply_hysteresis,
    build_confusion_matrix,
    classify,
    init_hysteresis_state,
    is_untradeable_spread_or_liquidity,
)

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


# --- Bias/structure-input decision (TASK-031 Specification item 4) -------------
# swing_agreement/direction_agree remain caller-supplied per the module's own
# docstring decision; a "MarketStructure.mqh read failure" is therefore not a
# distinct failure path THIS classify() function can exhibit -- it manifests
# as the caller passing a neutral/no-bias input (swing_agreement=0.0,
# direction_agree=False), already exercised by several fixtures above
# (e.g. test_ranging_via_efficiency_failure,
# test_transition_when_expansion_but_direction_disagrees). This test states
# that explicitly rather than leaving the decision implicit.
def test_structure_read_failure_modeled_as_neutral_caller_supplied_bias():
    # Same shape as test_transition_when_expansion_but_direction_disagrees --
    # a caller whose own MarketStructure.mqh read failed would supply exactly
    # these neutral values, not a distinct "structure failed" signal this
    # module has no way to represent (see module docstring's own decision).
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
    assert result.valid is True  # classify() itself never fails on this --
    # only the STRUCTURE INPUT'S caller can distinguish "no bias" from
    # "read failure," a distinction this module deliberately does not
    # attempt (see module docstring).


# --- Non-finite/zero-divisor domain validation (Codex review finding, ----------
# seventh round, P1 finding 15) -------------------------------------------------
# A NaN current_atr previously slipped past the `current_atr <= 0.0` guard
# (NaN comparisons are always False in Python) and could still classify as a
# "valid" result; a zero trend_slope_atr_divisor previously raised a raw
# ZeroDivisionError instead of a clean domain error.


def test_classify_rejects_nan_current_atr():
    with pytest.raises(ValueError):
        classify(
            TREND_CLOSES,
            [0.0, 1.0, 1.0],
            float("nan"),
            ema_now=105.0,
            ema_prior=100.0,
            adx_now=50.0,
            **COMMON_KWARGS,
            swing_agreement=0.0,
            direction_agree=False,
        )


def test_classify_rejects_infinite_ema_now():
    with pytest.raises(ValueError):
        classify(
            TREND_CLOSES,
            [0.0, 1.0, 1.0],
            2.0,
            ema_now=float("inf"),
            ema_prior=100.0,
            adx_now=50.0,
            **COMMON_KWARGS,
            swing_agreement=0.0,
            direction_agree=False,
        )


def test_classify_rejects_zero_trend_slope_atr_divisor():
    kwargs = dict(COMMON_KWARGS)
    kwargs["trend_slope_atr_divisor"] = 0.0
    with pytest.raises(ValueError):
        classify(
            TREND_CLOSES,
            [0.0, 1.0, 1.0],
            2.0,
            ema_now=105.0,
            ema_prior=100.0,
            adx_now=50.0,
            **kwargs,
            swing_agreement=0.0,
            direction_agree=False,
        )


def test_classify_rejects_non_finite_closes():
    bad_closes = [104.0, float("nan"), 102.0, 101.0, 100.0]
    with pytest.raises(ValueError):
        classify(
            bad_closes,
            [0.0, 1.0, 1.0],
            2.0,
            ema_now=105.0,
            ema_prior=100.0,
            adx_now=50.0,
            **COMMON_KWARGS,
            swing_agreement=0.0,
            direction_agree=False,
        )


# --- is_untradeable_spread_or_liquidity (gating override) ----------------------
# Cross-checked directly against Test_MarketRegimeEngine.mq5's own hand-traced
# assertions (section 8) -- identical input values, identical expected results.


def test_gating_wide_spread_triggers():
    assert is_untradeable_spread_or_liquidity(1.0, 2.0, 0.15, 10.0, 5.0) is True


def test_gating_low_liquidity_triggers():
    assert is_untradeable_spread_or_liquidity(0.1, 2.0, 0.15, 2.0, 5.0) is True


def test_gating_normal_conditions_do_not_trigger():
    assert is_untradeable_spread_or_liquidity(0.1, 2.0, 0.15, 10.0, 5.0) is False


# --- Hysteresis (apply_hysteresis / RegimeHysteresisState) ---------------------
# Cross-checked directly against Test_MarketRegimeEngine.mq5's own hand-traced
# 5-step scenario (section 7) -- identical sequence, identical expected results.


def test_hysteresis_full_scenario_matches_mql5_cross_check():
    state = init_hysteresis_state()

    e1 = apply_hysteresis(state, Regime.TRENDING_UP, False, 2)
    assert e1 == Regime.TRANSITION_OR_UNCERTAIN  # first read of a new regime, not yet confirmed

    e2 = apply_hysteresis(state, Regime.TRENDING_UP, False, 2)
    assert e2 == Regime.TRENDING_UP  # second consecutive matching read confirms it

    e3 = apply_hysteresis(state, Regime.RANGING, False, 2)
    assert e3 == Regime.TRENDING_UP  # a single differing read does not yet switch

    e4 = apply_hysteresis(state, Regime.RANGING, False, 2)
    assert e4 == Regime.RANGING  # a second consecutive differing read switches

    e5 = apply_hysteresis(state, Regime.NEWS_BLACKOUT, True, 2)
    assert e5 == Regime.NEWS_BLACKOUT  # bypass takes effect immediately


def test_apply_hysteresis_rejects_non_positive_required_bars():
    """Codex review finding (seventh round, P1 finding 15):
    required_bars=0 was previously accepted even though a confirmation-bar
    count must be positive -- required_bars=0 makes
    `pending_count >= required_bars` true on the FIRST ever pending read,
    confirming a regime with zero actual hysteresis at all."""

    state = init_hysteresis_state()
    with pytest.raises(ValueError):
        apply_hysteresis(state, Regime.TRENDING_UP, False, required_bars=0)
    with pytest.raises(ValueError):
        apply_hysteresis(state, Regime.TRENDING_UP, False, required_bars=-1)


def test_hysteresis_borderline_flapping_input_never_confirms():
    # A raw regime that flips every single bar must never confirm a switch --
    # pending_count resets to 1 on every differing read, never reaching
    # required_bars.
    state = init_hysteresis_state()
    sequence = [Regime.TRENDING_UP, Regime.RANGING, Regime.TRENDING_UP, Regime.RANGING]
    for raw in sequence:
        effective = apply_hysteresis(state, raw, False, required_bars=2)
        assert effective == Regime.TRANSITION_OR_UNCERTAIN
    assert state.has_confirmed is False


def test_hysteresis_sustained_switch_across_required_bars_confirms():
    state = init_hysteresis_state()
    # Confirm TRENDING_UP first.
    apply_hysteresis(state, Regime.TRENDING_UP, False, required_bars=3)
    apply_hysteresis(state, Regime.TRENDING_UP, False, required_bars=3)
    confirmed = apply_hysteresis(state, Regime.TRENDING_UP, False, required_bars=3)
    assert confirmed == Regime.TRENDING_UP
    assert state.has_confirmed is True

    # Now a genuine sustained switch to COMPRESSION across 3 consecutive reads.
    e1 = apply_hysteresis(state, Regime.COMPRESSION, False, required_bars=3)
    assert e1 == Regime.TRENDING_UP  # still reporting the old confirmed regime
    e2 = apply_hysteresis(state, Regime.COMPRESSION, False, required_bars=3)
    assert e2 == Regime.TRENDING_UP
    e3 = apply_hysteresis(state, Regime.COMPRESSION, False, required_bars=3)
    assert e3 == Regime.COMPRESSION  # confirmed after exactly required_bars


def test_hysteresis_pre_first_confirmation_reports_transition_not_a_guess():
    state = init_hysteresis_state()
    assert state.has_confirmed is False
    effective = apply_hysteresis(state, Regime.VOLATILITY_EXPANSION_UP, False, required_bars=5)
    assert effective == Regime.TRANSITION_OR_UNCERTAIN
    assert state.has_confirmed is False


# --- RegimeTransitionHistory ----------------------------------------------------


def test_transition_history_records_only_genuine_confirmed_transitions():
    history = RegimeTransitionHistory(max_entries=10)

    # First call ever -- nothing to transition FROM yet, must not record.
    history.record_confirmed(1, Regime.TRENDING_UP, True)
    assert len(history) == 0

    # Repeated confirmation of the SAME regime -- never a transition.
    history.record_confirmed(2, Regime.TRENDING_UP, True)
    history.record_confirmed(3, Regime.TRENDING_UP, True)
    assert len(history) == 0

    # A genuine change -- exactly one transition recorded.
    history.record_confirmed(4, Regime.RANGING, True)
    assert len(history) == 1
    assert history.entries[0].timestamp == 4
    assert history.entries[0].from_regime == Regime.TRENDING_UP
    assert history.entries[0].to_regime == Regime.RANGING

    # Another genuine change.
    history.record_confirmed(5, Regime.COMPRESSION, True)
    assert len(history) == 2
    assert history.entries[1].from_regime == Regime.RANGING
    assert history.entries[1].to_regime == Regime.COMPRESSION


def test_transition_history_evicts_oldest_entry_at_capacity():
    history = RegimeTransitionHistory(max_entries=2)
    history.record_confirmed(0, Regime.TRENDING_UP, True)  # seeds _last_confirmed_regime, no entry
    history.record_confirmed(1, Regime.RANGING, True)  # transition 1: TRENDING_UP -> RANGING
    history.record_confirmed(2, Regime.COMPRESSION, True)  # transition 2: RANGING -> COMPRESSION
    assert len(history) == 2

    # A third transition exceeds capacity -- the OLDEST entry is evicted.
    history.record_confirmed(3, Regime.TRENDING_DOWN, True)  # transition 3: COMPRESSION -> TRENDING_DOWN
    assert len(history) == 2
    assert history.entries[0].from_regime == Regime.RANGING  # transition 1 evicted
    assert history.entries[0].to_regime == Regime.COMPRESSION
    assert history.entries[1].from_regime == Regime.COMPRESSION
    assert history.entries[1].to_regime == Regime.TRENDING_DOWN


def test_transition_history_rejects_non_positive_max_entries():
    with pytest.raises(ValueError):
        RegimeTransitionHistory(max_entries=0)


def test_transition_history_ignores_pre_confirmation_sentinel_calls():
    """Codex review finding (seventh round, P1 finding 15): before
    hysteresis's first genuine confirmation, apply_hysteresis() returns the
    TRANSITION_OR_UNCERTAIN sentinel -- calling record_confirmed with that
    sentinel and has_confirmed=False (the real caller pattern, threading
    state.has_confirmed straight through) must never seed
    _last_confirmed_regime nor record a phantom transition once the FIRST
    real confirmation later arrives."""

    history = RegimeTransitionHistory(max_entries=10)

    # Several bars before hysteresis has confirmed anything -- these must
    # be ignored entirely, exactly mirroring what a caller thread would
    # look like: apply_hysteresis() returns TRANSITION_OR_UNCERTAIN,
    # state.has_confirmed is still False.
    history.record_confirmed(1, Regime.TRANSITION_OR_UNCERTAIN, False)
    history.record_confirmed(2, Regime.TRANSITION_OR_UNCERTAIN, False)
    assert len(history) == 0

    # The FIRST genuine confirmation must NOT be recorded as a transition
    # FROM the sentinel -- there is nothing to transition from yet.
    history.record_confirmed(3, Regime.TRENDING_UP, True)
    assert len(history) == 0

    # A genuine subsequent change IS recorded, and correctly FROM
    # TRENDING_UP (the first real confirmation), never from the sentinel.
    history.record_confirmed(4, Regime.RANGING, True)
    assert len(history) == 1
    assert history.entries[0].from_regime == Regime.TRENDING_UP
    assert history.entries[0].to_regime == Regime.RANGING


def test_transition_history_entries_property_is_a_defensive_copy():
    history = RegimeTransitionHistory(max_entries=10)
    history.record_confirmed(0, Regime.TRENDING_UP, True)
    history.record_confirmed(1, Regime.RANGING, True)

    entries = history.entries
    entries.append("not_a_real_entry")  # mutating the returned list itself
    assert len(history) == 1  # the internal buffer must be unaffected
