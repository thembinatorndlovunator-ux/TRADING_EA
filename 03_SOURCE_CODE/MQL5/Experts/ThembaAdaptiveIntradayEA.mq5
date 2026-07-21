//+------------------------------------------------------------------+
//| ThembaAdaptiveIntradayEA.mq5                                      |
//| Themba Adaptive Intraday Engine                                    |
//|                                                                    |
//| The first real Expert Advisor entry point in this project — wires    |
//| every module built across TASK-003 through TASK-026 into one          |
//| once-per-completed-bar decision pipeline: classify regime, evaluate    |
//| every strategy against the same shared data, route, resolve             |
//| conflicts, journal the result, and — as of TASK-027, ONLY when           |
//| InpEnableOrderSubmission is explicitly set true — submit a real,          |
//| fully-risk-gated order for the winning candidate.                          |
//|                                                                    |
//| **MASTER SAFETY TOGGLE: InpEnableOrderSubmission (default FALSE).**      |
//| With the default, this EA behaves EXACTLY as TASK-025 shipped it —        |
//| journal-only, never submits an order, regardless of any decision.          |
//| Setting it true makes this build capable of real order submission,          |
//| gated by every risk control built through TASK-026: no-add-on/no-           |
//| concurrent-position rule, daily/weekly loss caps (DailyWeeklyLimits),        |
//| drawdown-based risk reduction (EquityPeakManager/DrawdownController),         |
//| stop floor/cap preflight, broker-minimum-volume-vs-cap rejection, and          |
//| the OrderCalcProfit cross-check — every one of section 8's binding              |
//| blanket rules from TASK-002_PHASE2_SPECIFICATION.md. See                          |
//| TASK-027_WIRE_ORDER_MANAGER.md for the full gating sequence and the                |
//| gaps this task explicitly does NOT close (three-loss cooldown,                     |
//| durable-intent/idempotency persistence, forced close-all on a loss-cap               |
//| breach — that remains ExitManager/IntradayCloseManager territory).                    |
//|                                                                    |
//| The one place this EA touches live trading state outside               |
//| AttemptOrderSubmission is IntradayCloseManager.mqh's boundary close,      |
//| scoped strictly to this EA's own magic number — with                       |
//| InpEnableOrderSubmission false that remains a no-op in practice, exactly     |
//| as TASK-025 documented; with it true, that close now has real positions       |
//| (this EA's own) to close at the daily boundary, which is its intended          |
//| purpose.                                                                        |
//+------------------------------------------------------------------+
#property strict
#property version   "1.01"
#property description "Themba Adaptive Intraday Engine — decision pipeline; order submission is OFF by default (TASK-027, InpEnableOrderSubmission)."

#include "../Include/ThembaEA/Routing/ConflictResolver.mqh"
#include "../Include/ThembaEA/Risk/BrokerValidator.mqh"
#include "../Include/ThembaEA/Risk/DailyWeeklyLimits.mqh"
#include "../Include/ThembaEA/Risk/EquityPeakManager.mqh"
#include "../Include/ThembaEA/Risk/DrawdownController.mqh"
#include "../Include/ThembaEA/Journal/DecisionJournal.mqh"
#include "../Include/ThembaEA/Execution/IntradayCloseManager.mqh"
#include "../Include/ThembaEA/Execution/OrderManager.mqh"

input string InpTradeSymbol      = "";       // empty = use the chart's own symbol
input ENUM_TIMEFRAMES InpRegimeTimeframe = PERIOD_M15;
input long   InpMagicNumber      = 990001;
input int    InpSwingDepth       = 3;
input int    InpMaxLookback      = 50;
input int    InpSharedWindowBars = 250;      // shared OHLC/ATR window for all strategy evaluations

input bool   InpEnableOrderSubmission     = false; // MASTER SAFETY TOGGLE — see file header
input double InpRiskPercentTarget         = 0.3;   // per-trade target risk %, within section 8's
                                                    // stated 0.25-0.50% metals/synthetics range
input double InpRiskCapPercent            = 1.0;   // hard per-trade/total-open-risk cap (section 8)
input double InpDailyLossCapPercent       = 2.0;   // section 8 hard limit
input double InpWeeklyLossCapPercent      = 4.0;   // section 8 hard limit
input double InpDrawdownMaxReductionPercent = 10.0; // DrawdownController default
input double InpDrawdownMinMultiplier     = 0.25;   // DrawdownController default
input double InpStopFloorAtrMultiple      = 0.5;    // RiskManager default
input double InpStopCapPricePercent       = 3.0;    // RiskManager default
input double InpStopCapAtrMultiple        = 4.0;    // RiskManager default
input double InpRiskCrossCheckTolerancePercent = 5.0; // section 8 default

CMarketData     g_md;
CSymbolProfile  g_profile;
string          g_symbol;
datetime        g_last_evaluated_bar_time = 0;

int OnInit()
  {
   g_symbol = (InpTradeSymbol == "") ? _Symbol : InpTradeSymbol;

   if(!g_profile.Load(g_symbol))
     {
      PrintFormat("ThembaEA: symbol profile failed to load for '%s' — refusing to run.", g_symbol);
      return INIT_FAILED;
     }

   string reasons[];
   if(!BV_ValidateSymbolProfile(g_profile, reasons))
     {
      for(int i = 0; i < ArraySize(reasons); i++)
         PrintFormat("ThembaEA: broker validation failed: %s", reasons[i]);
      return INIT_FAILED;
     }

   if(!g_md.Init(g_symbol, InpRegimeTimeframe))
     {
      PrintFormat("ThembaEA: MarketData init failed for '%s' on %s.", g_symbol,
                  EnumToString(InpRegimeTimeframe));
      return INIT_FAILED;
     }

   if(InpEnableOrderSubmission)
      PrintFormat("ThembaEA: initialized for '%s' on %s. *** ORDER SUBMISSION IS ENABLED *** "
                  "(InpEnableOrderSubmission=true) — this build WILL place real orders when a "
                  "decision clears every risk gate.", g_symbol, EnumToString(InpRegimeTimeframe));
   else
      PrintFormat("ThembaEA: initialized for '%s' on %s. JOURNAL-ONLY MODE — no order will "
                  "be submitted (InpEnableOrderSubmission=false).", g_symbol,
                  EnumToString(InpRegimeTimeframe));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   PrintFormat("ThembaEA: deinitialized, reason=%d.", reason);
  }

void OnTick()
  {
   datetime current_bar_time;
   if(!g_md.GetTime(0, current_bar_time))
      return;
   if(current_bar_time == g_last_evaluated_bar_time)
      return; // only evaluate once per newly completed bar
   g_last_evaluated_bar_time = current_bar_time;

   EvaluateAndJournal();

   // Scoped strictly to this EA's own magic number. With
   // InpEnableOrderSubmission=false this remains a no-op in practice
   // (nothing is ever opened under this magic); with it true, this is
   // now this EA's real end-of-day exposure close.
   if(ICM_ShouldExecuteIntradayClose())
     {
      string closeReasons[];
      ICM_ExecuteIntradayClose(InpMagicNumber, closeReasons);
     }
  }

//--- Appends one string to a dynamic string[] array (local helper —
//--- mirrors the ICM_AppendReason/BV_AppendReason pattern used
//--- throughout this project for machine-readable reason lists).
void AppendReason(string &arr[], const string value)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = value;
  }

//--- Serializes a string[] array of machine-readable reason tokens to a
//--- JSON array, reusing DecisionJournal's own escaping so this stays
//--- consistent with every other string field the journal writes.
string BuildJsonStringArray(const string &arr[])
  {
   string json = "[";
   for(int i = 0; i < ArraySize(arr); i++)
     {
      if(i > 0)
         json += ",";
      json += "\"" + DJ_JsonEscapeString(arr[i]) + "\"";
     }
   json += "]";
   return json;
  }

//+------------------------------------------------------------------+
//| Gates and, if every check passes, submits a real order for the       |
//| resolved winning candidate. Only ever called when                     |
//| InpEnableOrderSubmission is true (see AttemptOrderSubmission's own      |
//| caller). Every rejection path appends a machine-readable reason to      |
//| 'rejected' and returns without submitting — a caller must treat           |
//| decision.risk_percent staying 0.0 as "no order was placed", never          |
//| infer success from decision.direction alone (that field reflects the        |
//| strategy's PROPOSED direction regardless of whether an order followed).      |
//|                                                                    |
//| Gating sequence, in order (matches TASK-027_WIRE_ORDER_MANAGER.md's   |
//| Specification section):                                               |
//|  1. No-add-on/no-concurrent-position rule (section 8).                  |
//|  2. Daily/weekly loss caps, account-wide measurement (section 8).         |
//|  3. Drawdown-based risk reduction, never increase (section 8).             |
//|  4. Stop-distance floor/cap preflight (section 8, RiskManager.mqh).          |
//|  5. Position sizing incl. broker-minimum-vs-cap rejection (OrderManager).     |
//|  6. OrderCalcProfit cross-check (RISK_POLICY.md blanket rule).                 |
//|  7. Real order submission (OrderManager.mqh).                                   |
//+------------------------------------------------------------------+
void AttemptOrderSubmission(STradeDecision &decision, const SConflictResult &resolution,
                             const double atr_current)
  {
   string passed[];
   string rejected[];

   //--- 1. No-add-on / no-concurrent-position rule -----------------------
   bool already_open = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      already_open = true;
      break;
     }
   if(already_open)
     {
      AppendReason(rejected, "position_already_open_no_add_on");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   //--- 2. Daily/weekly loss caps (account-wide measurement) -------------
   double daily_change;
   if(DWL_IsDailyLossBreached(InpDailyLossCapPercent, daily_change))
     {
      AppendReason(rejected, StringFormat("daily_loss_cap_breached_change_%.4fpct", daily_change));
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   double weekly_change;
   if(DWL_IsWeeklyLossBreached(InpWeeklyLossCapPercent, weekly_change))
     {
      AppendReason(rejected, StringFormat("weekly_loss_cap_breached_change_%.4fpct", weekly_change));
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   AppendReason(passed, "daily_weekly_loss_caps_clear");

   //--- 3. Drawdown-based risk reduction (never increase) ----------------
   double current_drawdown = EPM_GetCurrentDrawdownPercent();
   double risk_multiplier = DC_ComputeRiskMultiplier(current_drawdown,
                                                       InpDrawdownMaxReductionPercent,
                                                       InpDrawdownMinMultiplier);
   double effective_risk_percent = InpRiskPercentTarget * risk_multiplier;
   AppendReason(passed, StringFormat("risk_multiplier_%.4f_drawdown_%.4fpct",
                                       risk_multiplier, current_drawdown));

   //--- 4. Stop-distance floor/cap preflight ------------------------------
   bool is_long = (resolution.winning_direction == CAND_LONG);
   double entry = resolution.winner.entry_price;
   double proposed_stop = resolution.winner.stop_price;
   double loss_distance = RM_ComputeLossDistance(is_long, entry, proposed_stop);

   double min_stop = RM_ComputeMinStopDistance(atr_current, InpStopFloorAtrMultiple);
   double max_stop = RM_ComputeMaxStopDistance(entry, atr_current, InpStopCapPricePercent,
                                                 InpStopCapAtrMultiple);
   double adjusted_loss_distance;
   string stop_reason;
   if(!RM_ValidateStopDistance(loss_distance, min_stop, max_stop, adjusted_loss_distance,
                                stop_reason))
     {
      AppendReason(rejected, "stop_" + stop_reason);
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   if(stop_reason == "widened_to_floor")
      AppendReason(passed, "stop_widened_to_floor");

   double final_stop = is_long ? entry - adjusted_loss_distance : entry + adjusted_loss_distance;

   //--- 5. Position sizing -------------------------------------------------
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   SOrderSizingResult sizing;
   if(!OM_CalculateVolume(g_profile, equity, effective_risk_percent, adjusted_loss_distance,
                            InpRiskCapPercent, sizing))
     {
      AppendReason(rejected, "sizing_" + sizing.rejection_reason);
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   if(sizing.widened_to_minimum)
      AppendReason(passed, "volume_widened_to_broker_minimum");

   //--- 6. OrderCalcProfit cross-check --------------------------------------
   double broker_risk_cash;
   bool cross_ok = RM_CrossCheckRiskCash(g_symbol, is_long, sizing.volume, entry, final_stop,
                                          sizing.risk_cash_actual, broker_risk_cash,
                                          InpRiskCrossCheckTolerancePercent);
   if(!cross_ok)
     {
      AppendReason(rejected, StringFormat(
         "risk_cross_check_failed_computed_%.4f_broker_%.4f",
         sizing.risk_cash_actual, broker_risk_cash));
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   AppendReason(passed, "risk_cross_check_passed");

   //--- 7. Submit the real order --------------------------------------------
   string comment = StringFormat("Themba_%s", decision.strategy);
   if(StringLen(comment) > 31)
      comment = StringSubstr(comment, 0, 31); // MT5 order-comment length limit

   SOrderOpenResult open_result;
   bool opened = OM_OpenPosition(g_symbol, is_long, sizing.volume, final_stop,
                                   resolution.winner.target_price, InpMagicNumber, comment,
                                   open_result);
   if(!opened)
     {
      AppendReason(rejected, "order_" + open_result.rejection_reason);
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   // Success — reflect the ACTUAL submitted stop back into the journal
   // record (a floor widening in step 4 may have moved it from the
   // strategy's originally proposed stop).
   decision.stop = final_stop;
   decision.risk_percent = 100.0 * sizing.risk_cash_actual / equity;
   AppendReason(passed, StringFormat("order_submitted_ticket_%I64u_volume_%.2f_fill_%.5f",
                                       open_result.position_ticket, sizing.volume,
                                       open_result.fill_price));
   PrintFormat("ThembaEA: *** ORDER SUBMITTED *** %s %s volume=%.2f ticket=%I64u fill=%.5f "
               "stop=%.5f risk_pct=%.4f", decision.direction, g_symbol, sizing.volume,
               open_result.position_ticket, open_result.fill_price, final_stop,
               decision.risk_percent);

   decision.reasons_passed_json = BuildJsonStringArray(passed);
   decision.reasons_rejected_json = BuildJsonStringArray(rejected);
  }

//+------------------------------------------------------------------+
//| Classifies the regime once, reads the shared OHLC/ATR window once,   |
//| computes structure once, evaluates all five strategies against that   |
//| SAME data, routes, resolves, journals the outcome, and — only when     |
//| InpEnableOrderSubmission is true — attempts a fully risk-gated real     |
//| order submission for the winning candidate (see file header).          |
//+------------------------------------------------------------------+
void EvaluateAndJournal()
  {
   // Account-wide bookkeeping runs every bar regardless of this bar's
   // decision outcome, per section 8 — equity tracking must not skip a
   // bar just because regime classification later fails or no strategy
   // fires.
   DWL_EnsureDailyBaseline();
   DWL_EnsureWeeklyBaseline();
   DWL_ApplyCashFlowAdjustments();
   EPM_UpdateDailyPeak();
   EPM_UpdateAccountPeak();

   const int    atr_percentile_window = 100;
   const int    efficiency_window     = 20;
   const int    ema_period            = 21;
   const int    ema_slope_bars        = 5;
   const int    adx_period            = 14;
   const double trend_threshold       = 0.6;
   const double expansion_threshold   = 0.75;
   const double compression_threshold = 0.25;
   const double min_efficiency        = 0.3;
   const double trend_slope_divisor   = 0.5;

   SRegimeRead regime_read;
   if(!MRE_ClassifyLive(g_md, atr_percentile_window, efficiency_window, ema_period, ema_slope_bars,
                         adx_period, InpSwingDepth, InpMaxLookback, trend_threshold,
                         expansion_threshold, compression_threshold, min_efficiency,
                         trend_slope_divisor, regime_read))
     {
      Print("ThembaEA: regime classification failed this bar (insufficient data or "
            "indicator failure) — skipping evaluation.");
      return;
     }

   if(!g_md.HasBars(InpSharedWindowBars))
     {
      Print("ThembaEA: insufficient history for the shared evaluation window — skipping.");
      return;
     }

   double opens[], highs[], lows[], closes[], atr_values[];
   ArrayResize(opens, InpSharedWindowBars);
   ArrayResize(highs, InpSharedWindowBars);
   ArrayResize(lows, InpSharedWindowBars);
   ArrayResize(closes, InpSharedWindowBars);
   ArrayResize(atr_values, InpSharedWindowBars);
   for(int i = 0; i < InpSharedWindowBars; i++)
     {
      if(!g_md.GetOpen(i, opens[i]) || !g_md.GetHigh(i, highs[i]) || !g_md.GetLow(i, lows[i]) ||
         !g_md.GetClose(i, closes[i]) || !g_md.GetATR(i, atr_values[i], 14))
        {
         Print("ThembaEA: a required price/ATR read failed — skipping this bar's evaluation.");
         return;
        }
     }

   SMarketStructureState structure;
   MS_ComputeStructureArray(highs, lows, closes, InpSwingDepth, InpMaxLookback, structure);

   STradeCandidate candidates[5];

   // 1. SR Bounce
   SSRBounceSignal srSig;
   SRB_EvaluateArray(opens, highs, lows, closes, atr_values, InpSwingDepth, InpMaxLookback,
                      regime_read.regime, structure, 0.3, 2, 0.3, 5, srSig);
   candidates[0] = SS_FromSRBounce(srSig);

   // 2. SMC/ICT
   SSMCConfig smcCfg;
   smcCfg.depth = InpSwingDepth; smcCfg.max_lookback = InpMaxLookback;
   smcCfg.displacement_atr_multiple = 1.5; smcCfg.retest_tolerance_atr = 0.3;
   smcCfg.max_retest_bars = 10; smcCfg.sweep_lookback = 30; smcCfg.shift_lookback = 6;
   smcCfg.fvg_scan_bars = 15; smcCfg.trend_lookback = 5;
   SSMCSignal smcSig;
   SMC_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, smcCfg, smcSig);
   candidates[1] = SS_FromSMC(smcSig);

   // 3. Chart Pattern
   SCPStrategyConfig cpCfg;
   cpCfg.depth = InpSwingDepth; cpCfg.max_lookback = InpMaxLookback;
   cpCfg.price_tolerance_atr = 1.0; cpCfg.min_pullback_atr = 1.5;
   cpCfg.min_head_prominence_atr = 1.0; cpCfg.time_tolerance = 0.5;
   cpCfg.trend_bars = 10; cpCfg.breakout_buffer_atr = 0.1; cpCfg.max_breakout_age_bars = 15;
   cpCfg.retest_tolerance_atr = 0.3; cpCfg.candlestick_trend_lookback = 5;
   SChartPatternStrategySignal cpSig;
   CPS_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, structure, cpCfg,
                      cpSig);
   candidates[2] = SS_FromChartPattern(cpSig);

   // 4. Trend Following
   STFConfig tfCfg;
   tfCfg.depth = InpSwingDepth; tfCfg.max_lookback = InpMaxLookback;
   tfCfg.middle_tolerance_atr = 0.5; tfCfg.touch_tolerance_atr = 0.3;
   tfCfg.stop_buffer_atr = 0.1; tfCfg.momentum_lookback_bars = 10;
   tfCfg.displacement_atr_multiple = 1.5; tfCfg.max_pullback_atr = 1.0;
   tfCfg.momentum_stop_atr = 1.5; tfCfg.candlestick_trend_lookback = 5;
   STFStrategySignal tfSig;
   TFS_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, tfCfg, tfSig);
   candidates[3] = SS_FromTrendFollowing(tfSig);

   // 5. Post-Expansion Retest
   SPERConfig perCfg;
   perCfg.depth = InpSwingDepth; perCfg.max_lookback = InpMaxLookback;
   perCfg.min_expansion_atr = 1.5; perCfg.retest_tolerance_atr = 0.3;
   perCfg.no_chase_bars = 2; perCfg.stop_buffer_atr = 0.1; perCfg.candlestick_trend_lookback = 5;
   SPostExpansionRetestSignal perSig;
   PER_EvaluateArray(opens, highs, lows, closes, atr_values, regime_read.regime, structure, perCfg,
                      perSig);
   candidates[4] = SS_FromPostExpansionRetest(perSig);

   SRoutedCandidate routed[];
   int eligible_count = STR_RouteCandidates(candidates, 5, regime_read.regime,
                                             regime_read.confidence, routed);

   SConflictResult resolution;
   bool has_decision = CR_ResolveConflicts(routed, 5, 10.0, resolution);

   STradeDecision decision = DJ_NewDecision();
   decision.timestamp = TimeCurrent();
   decision.symbol = g_symbol;
   decision.regime = EnumToString(regime_read.regime);
   decision.regime_confidence = regime_read.confidence * 100.0;
   decision.ea_version = "1.01-task027-order-submission-optional";

   if(has_decision)
     {
      decision.direction = (resolution.winning_direction == CAND_LONG) ? "BUY" : "SELL";
      decision.strategy = EnumToString(resolution.winner.family);
      decision.setup = resolution.winner.setup;
      decision.candlestick_pattern = resolution.winner.candlestick_pattern;
      decision.entry = resolution.winner.entry_price;
      decision.has_entry = true;
      decision.stop = resolution.winner.stop_price;
      decision.has_stop = true;
      decision.targets_json = StringFormat("[%.5f]", resolution.winner.target_price);
      decision.score = resolution.winner_score;
      PrintFormat("ThembaEA: decision = %s %s via %s (%s), score=%.2f", decision.direction,
                  g_symbol, decision.strategy, decision.setup, decision.score);

      if(InpEnableOrderSubmission)
         AttemptOrderSubmission(decision, resolution, atr_values[0]);
      else
        {
         string skip_reasons[];
         AppendReason(skip_reasons, "order_submission_disabled_InpEnableOrderSubmission_false");
         decision.reasons_rejected_json = BuildJsonStringArray(skip_reasons);
         Print("ThembaEA: JOURNAL ONLY — no order submitted (InpEnableOrderSubmission=false).");
        }
     }
   else
     {
      decision.direction = "NONE";
      decision.strategy = "NoTrade";
      decision.setup = resolution.reason;
     }

   string journal_error;
   if(!DJ_AppendDecision(decision, journal_error))
      PrintFormat("ThembaEA: failed to journal this bar's decision: %s", journal_error);
  }
