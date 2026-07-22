//+------------------------------------------------------------------+
//| IntradayModeRouter.mqh                                            |
//| Themba Adaptive Intraday Engine — Market                          |
//|                                                                    |
//| TASK-040 — the market_family classifier, per                        |
//| 00_MASTER_PROMPT_FOR_CLAUDE.md section 5 and section 18's symbol-       |
//| family requirement (Codex review finding, sixth round, P0 finding 3:      |
//| "Live mode classification... remain[s] unowned").                          |
//|                                                                    |
//| **Rewritten, 2026-07-22 (Codex review finding, seventh round, P0        |
//| finding 6): the previous intraday_mode classifier was this task's own       |
//| ad hoc scoring formula, explicitly flagged as "not spec-verbatim" -- the       |
//| review found that TASK-002_PHASE2_SPECIFICATION.md section 1 actually            |
//| DOES fully specify an executable mode formula (four normalized                     |
//| components, configurable weights, explicit missing-data severity rules,             |
//| 0.40/0.60 thresholds, neutral-band persistence, two-consecutive-bar                    |
//| hysteresis) that this module never implemented. This rewrite implements                 |
//| that approved formula directly, not a re-derived approximation.**                          |
//|                                                                    |
//| **Stated, honest deviation from the canonical spec (not silently             |
//| glossed over): the spec's hysteresis confirmation is defined in TWO             |
//| CONSECUTIVE CLOSED M1 BARS, independent of whichever timeframe the                 |
//| regime/mode formula itself runs on. This EA's own decision pipeline                   |
//| (EvaluateAndJournal) only evaluates once per InpRegimeTimeframe bar (M15               |
//| by default) -- it has no independent M1-tick-level hook. This module's                   |
//| own hysteresis therefore confirms across two consecutive EVALUATIONS of                    |
//| IMR_ApplyModeHysteresis (i.e., two consecutive M15-cadence decision                          |
//| bars in the current wiring), not two consecutive M1 bars specifically.                         |
//| This is MORE conservative (slower to confirm a mode switch) than the                             |
//| spec's own M1-bar cadence, never less -- but it is not literally what                               |
//| section 1 specifies. Building a genuine M1-tick-independent hysteresis                                |
//| hook is a further, explicitly named follow-up, not attempted here under                                 |
//| review-remediation time pressure.**                                                                        |
//|                                                                    |
//| Historical-performance-conditioned scoring (spec's own dropped                |
//| component, never part of this formula per TASK-002 section 1's own            |
//| "components requiring a candidate are removed" note) remains out of              |
//| scope, as it always was.                                                              |
//+------------------------------------------------------------------+
#property strict

#include "MarketRegimeEngine.mqh"

enum ENUM_MARKET_FAMILY
  {
   MARKET_FAMILY_METAL,
   MARKET_FAMILY_FOREX,
   MARKET_FAMILY_SYNTHETIC_INDEX,
   MARKET_FAMILY_UNKNOWN
  };

string IMR_MarketFamilyToString(const ENUM_MARKET_FAMILY family)
  {
   switch(family)
     {
      case MARKET_FAMILY_METAL:            return "METAL";
      case MARKET_FAMILY_FOREX:             return "FOREX";
      case MARKET_FAMILY_SYNTHETIC_INDEX:   return "SYNTHETIC_INDEX";
      default:                              return "UNKNOWN";
     }
  }

enum ENUM_INTRADAY_MODE
  {
   INTRADAY_MODE_SCALP,
   INTRADAY_MODE_DAY_TRADE,
   INTRADAY_MODE_NONE // fail-closed / no-mode -- gating override or undefined mode_score
  };

string IMR_IntradayModeToString(const ENUM_INTRADAY_MODE mode)
  {
   switch(mode)
     {
      case INTRADAY_MODE_DAY_TRADE: return "DAY_TRADE";
      case INTRADAY_MODE_SCALP:     return "SCALP";
      default:                      return "NONE";
     }
  }

//+------------------------------------------------------------------+
//| Classifies 'symbol' via the broker's own curated SYMBOL_PATH (see    |
//| file header for why this differs from a ticker-name heuristic).       |
//| Returns MARKET_FAMILY_UNKNOWN if the path contains no recognizable      |
//| keyword — never guessed from the ticker itself.                           |
//+------------------------------------------------------------------+
ENUM_MARKET_FAMILY IMR_ClassifyMarketFamily(const string symbol)
  {
   string path = SymbolInfoString(symbol, SYMBOL_PATH);
   string path_lower = path;
   StringToLower(path_lower);

   if(StringFind(path_lower, "synthetic") >= 0 || StringFind(path_lower, "volatility") >= 0 ||
      StringFind(path_lower, "boom") >= 0 || StringFind(path_lower, "crash") >= 0 ||
      StringFind(path_lower, "step index") >= 0 || StringFind(path_lower, "jump") >= 0 ||
      StringFind(path_lower, "range break") >= 0 || StringFind(path_lower, "drift switch") >= 0)
      return MARKET_FAMILY_SYNTHETIC_INDEX;

   if(StringFind(path_lower, "metal") >= 0)
      return MARKET_FAMILY_METAL;

   if(StringFind(path_lower, "forex") >= 0 || StringFind(path_lower, "currenc") >= 0)
      return MARKET_FAMILY_FOREX;

   return MARKET_FAMILY_UNKNOWN;
  }

//+------------------------------------------------------------------+
//| Per-component input: 'available' false means "hard failure" (an        |
//| indicator handle invalid, or less than half the ideal window available)   |
//| per TASK-002 section 1's own missing-data severity rule -- the caller      |
//| computes availability, this module only consumes it.                          |
//+------------------------------------------------------------------+
struct SModeComponent
  {
   bool   available;
   double value; // already normalized to [0,1], 1.0 favors Day-trade
  };

struct SModeWeights
  {
   double regime_persistence;
   double atr_percentile;
   double range_vs_average;
   double session_time_remaining;
  };

SModeWeights IMR_DefaultModeWeights()
  {
   SModeWeights w;
   w.regime_persistence = 0.25;
   w.atr_percentile = 0.25;
   w.range_vs_average = 0.25;
   w.session_time_remaining = 0.25;
   return w;
  }

struct SModeScoreResult
  {
   bool   valid; // false = mode_score undefined (all components unavailable, or hard-failure
                  // leaves fewer than 2 of 4 available) -- fail-closed, no mode.
   double mode_score;
   int    components_available;
  };

//+------------------------------------------------------------------+
//| PURE — direct port of TASK-002_PHASE2_SPECIFICATION.md section 1's    |
//| mode-score aggregation: "mode_score = Sum(weight_i x component_i) /       |
//| Sum(weight_i) over only the components actually available this              |
//| evaluation... If all four components are unavailable, or if the sum of        |
//| available weights is 0, mode_score is undefined." Per the same section's       |
//| hard-failure rule: if fewer than 2 of 4 components are available,                 |
//| mode_score is ALSO undefined (fail-closed), even if the available weight            |
//| sum is nonzero.                                                                        |
//+------------------------------------------------------------------+
SModeScoreResult IMR_ComputeModeScore(const SModeComponent &regime_persistence,
                                       const SModeComponent &atr_percentile,
                                       const SModeComponent &range_vs_average,
                                       const SModeComponent &session_time_remaining,
                                       const SModeWeights &weights)
  {
   SModeScoreResult r;
   r.valid = false;
   r.mode_score = 0.0;
   r.components_available = 0;

   double weight_sum = 0.0;
   double weighted_value_sum = 0.0;

   if(regime_persistence.available)
     {
      weight_sum += weights.regime_persistence;
      weighted_value_sum += weights.regime_persistence * regime_persistence.value;
      r.components_available++;
     }
   if(atr_percentile.available)
     {
      weight_sum += weights.atr_percentile;
      weighted_value_sum += weights.atr_percentile * atr_percentile.value;
      r.components_available++;
     }
   if(range_vs_average.available)
     {
      weight_sum += weights.range_vs_average;
      weighted_value_sum += weights.range_vs_average * range_vs_average.value;
      r.components_available++;
     }
   if(session_time_remaining.available)
     {
      weight_sum += weights.session_time_remaining;
      weighted_value_sum += weights.session_time_remaining * session_time_remaining.value;
      r.components_available++;
     }

   if(r.components_available < 2 || weight_sum <= 0.0)
      return r; // undefined -- fail-closed, matches invalid r.valid=false

   r.valid = true;
   r.mode_score = weighted_value_sum / weight_sum;
   return r;
  }

//+------------------------------------------------------------------+
//| Component 1: "regime persistence" = min(1, trend_age_bars /            |
//| InpModePersistenceBars) if the active directional regime is                  |
//| TRENDING_UP/DOWN; 0.3 for RANGING; 0.0 for any other regime. Direct           |
//| port of TASK-002 section 1's own formula.                                        |
//+------------------------------------------------------------------+
double IMR_ComputeRegimePersistence(const ENUM_MARKET_REGIME regime, const int trend_age_bars,
                                     const int persistence_window_bars)
  {
   if(regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN)
     {
      if(persistence_window_bars <= 0)
         return 0.0;
      return MathMin(1.0, (double)trend_age_bars / (double)persistence_window_bars);
     }
   if(regime == REGIME_RANGING)
      return 0.3;
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Component 3: "range-vs-average" = min(1, current_range_ATR_multiple /  |
//| 2.0). Direct port.                                                        |
//+------------------------------------------------------------------+
double IMR_ComputeRangeVsAverage(const double current_range_atr_multiple)
  {
   return MathMin(1.0, current_range_atr_multiple / 2.0);
  }

//+------------------------------------------------------------------+
//| Component 4: "session time remaining" = clamp01(remaining_session_     |
//| minutes / total_session_minutes), clamped to 0.0 below                       |
//| InpMinDayTradeSessionMinutes remaining. The caller supplies                      |
//| session_remaining_ratio already in [0,1] (SessionManager.mqh's own                 |
//| SN_GetSessionMinutesRemaining) and the remaining MINUTES separately for               |
//| the floor check (the ratio alone cannot recover absolute minutes).                       |
//+------------------------------------------------------------------+
double IMR_ComputeSessionTimeRemaining(const double session_remaining_ratio,
                                        const double remaining_session_minutes,
                                        const double min_day_trade_session_minutes)
  {
   if(remaining_session_minutes < min_day_trade_session_minutes)
      return 0.0;
   return MathMax(0.0, MathMin(1.0, session_remaining_ratio));
  }

//+------------------------------------------------------------------+
//| Caller-owned, persisted state: trend-age tracking (component 1) and     |
//| the mode hysteresis/neutral-band-persistence state machine (see file        |
//| header for the stated M1-vs-M15-evaluation-cadence deviation).                 |
//+------------------------------------------------------------------+
struct SModeState
  {
   int                trend_age_bars;
   ENUM_MARKET_REGIME last_directional_regime;
   bool               has_confirmed_mode;
   ENUM_INTRADAY_MODE confirmed_mode;
   ENUM_INTRADAY_MODE pending_mode;
   int                pending_count;
  };

void IMR_InitModeState(SModeState &state)
  {
   state.trend_age_bars = 0;
   state.last_directional_regime = REGIME_TRANSITION_OR_UNCERTAIN;
   state.has_confirmed_mode = false;
   state.confirmed_mode = INTRADAY_MODE_NONE;
   state.pending_mode = INTRADAY_MODE_NONE;
   state.pending_count = 0;
  }

//+------------------------------------------------------------------+
//| Call once per decision-pipeline evaluation, BEFORE computing            |
//| component 1, to advance the trend-age counter: increments while the         |
//| SAME directional regime persists, resets on any other regime (including       |
//| a direction FLIP from TRENDING_UP to TRENDING_DOWN, which is a genuinely           |
//| new trend, not a continuation).                                                       |
//+------------------------------------------------------------------+
void IMR_UpdateTrendAge(SModeState &state, const ENUM_MARKET_REGIME effective_regime)
  {
   if(effective_regime == REGIME_TRENDING_UP || effective_regime == REGIME_TRENDING_DOWN)
     {
      if(effective_regime == state.last_directional_regime)
         state.trend_age_bars++;
      else
        {
         state.last_directional_regime = effective_regime;
         state.trend_age_bars = 1;
        }
     }
   else
     {
      state.last_directional_regime = REGIME_TRANSITION_OR_UNCERTAIN;
      state.trend_age_bars = 0;
     }
  }

//+------------------------------------------------------------------+
//| Applies TASK-002 section 1's thresholds/precedence/hysteresis:         |
//| mode_score >= 0.60 -> Day-trade; <= 0.40 -> Scalp; otherwise neutral         |
//| band (previously-selected mode persists if one was already active, else       |
//| stays no-mode). A gating regime (NEWS_BLACKOUT/                                  |
//| UNTRADEABLE_SPREAD_OR_LIQUIDITY) or an undefined mode_score both force              |
//| INTRADAY_MODE_NONE immediately, bypassing hysteresis (matching section 1's            |
//| own "no mode, fail-closed" rule) -- mirrors MRE_ApplyHysteresis's own                   |
//| bypass convention exactly.                                                                 |
//+------------------------------------------------------------------+
ENUM_INTRADAY_MODE IMR_ApplyModeHysteresis(SModeState &state, const ENUM_MARKET_REGIME effective_regime,
                                            const SModeScoreResult &score,
                                            const int required_evaluations = 2)
  {
   bool gating_active = (effective_regime == REGIME_NEWS_BLACKOUT ||
                          effective_regime == REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY);

   if(gating_active || !score.valid)
     {
      state.confirmed_mode = INTRADAY_MODE_NONE;
      state.has_confirmed_mode = true;
      state.pending_mode = INTRADAY_MODE_NONE;
      state.pending_count = required_evaluations;
      return INTRADAY_MODE_NONE;
     }

   ENUM_INTRADAY_MODE raw_mode;
   bool in_neutral_band = false;
   if(score.mode_score >= 0.60)
      raw_mode = INTRADAY_MODE_DAY_TRADE;
   else if(score.mode_score <= 0.40)
      raw_mode = INTRADAY_MODE_SCALP;
   else
     {
      in_neutral_band = true;
      // Neutral band: previously-selected mode persists if one was already
      // active; otherwise stays no-mode until a threshold is cleared.
      raw_mode = state.has_confirmed_mode ? state.confirmed_mode : INTRADAY_MODE_NONE;
     }

   if(in_neutral_band)
     {
      // The neutral band does not itself go through the pending-count
      // confirmation machinery -- it directly carries forward whatever was
      // already confirmed (or stays NONE), per section 1's own single,
      // non-contradictory neutral-band statement.
      state.pending_mode = raw_mode;
      state.pending_count = required_evaluations;
      return raw_mode;
     }

   if(state.pending_mode != raw_mode)
     {
      state.pending_mode = raw_mode;
      state.pending_count = 1;
     }
   else
      state.pending_count++;

   if(state.pending_count >= required_evaluations)
     {
      state.confirmed_mode = raw_mode;
      state.has_confirmed_mode = true;
     }

   return state.has_confirmed_mode ? state.confirmed_mode : INTRADAY_MODE_NONE;
  }

//+------------------------------------------------------------------+
//| Stage 4's post-hoc mode-consistency check (TASK-002 section 1): "if    |
//| the candidate's own expected-R or distance-to-target is incompatible        |
//| with the selected mode (Day-trade candidate with expected R <                  |
//| InpMinDayTradeR, default 1.0; or Scalp candidate with expected R >               |
//| InpMaxScalpR, default 2.0), the candidate is rejected." This is what               |
//| makes intraday_mode actually ROUTE a trading decision, not stay purely               |
//| journal-only. A mode of INTRADAY_MODE_NONE rejects every candidate                     |
//| outright (no mode was confirmed, matching the gating/fail-closed rule).                  |
//+------------------------------------------------------------------+
bool IMR_IsCandidateConsistentWithMode(const ENUM_INTRADAY_MODE mode, const double expected_r,
                                        const double min_day_trade_r = 1.0,
                                        const double max_scalp_r = 2.0)
  {
   if(mode == INTRADAY_MODE_NONE)
      return false;
   if(mode == INTRADAY_MODE_DAY_TRADE)
      return expected_r >= min_day_trade_r;
   return expected_r <= max_scalp_r; // INTRADAY_MODE_SCALP
  }
