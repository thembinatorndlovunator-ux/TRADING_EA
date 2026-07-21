//+------------------------------------------------------------------+
//| ThembaAdaptiveIntradayEA.mq5                                      |
//| Themba Adaptive Intraday Engine                                    |
//|                                                                    |
//| The first real Expert Advisor entry point in this project — wires    |
//| every module built across TASK-003 through TASK-024 into one          |
//| once-per-completed-bar decision pipeline: classify regime, evaluate    |
//| every strategy against the same shared data, route, resolve             |
//| conflicts, and journal the result.                                       |
//|                                                                    |
//| **DELIBERATELY JOURNAL-ONLY — NEVER SUBMITS A REAL ORDER.** This is     |
//| a stated, hard scope boundary for this task, not a configurable          |
//| option: order submission (position sizing via RiskManager.mqh,           |
//| OrderManager.mqh, real risk-cap enforcement before submission) is a       |
//| separate, higher-stakes task that has not been attempted here. Running    |
//| this EA on a real or demo account is safe in the sense that it never      |
//| places, modifies, or closes any position it did not itself open — the     |
//| ONE exception is IntradayCloseManager.mqh's own boundary close, which      |
//| only ever acts on positions carrying this EA's own magic number, and       |
//| since this EA never opens any, that close path is a safe no-op in          |
//| practice until order submission exists.                                     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Themba Adaptive Intraday Engine — decision pipeline only, no order submission (TASK-025)."

#include "../Include/ThembaEA/Routing/ConflictResolver.mqh"
#include "../Include/ThembaEA/Risk/BrokerValidator.mqh"
#include "../Include/ThembaEA/Journal/DecisionJournal.mqh"
#include "../Include/ThembaEA/Execution/IntradayCloseManager.mqh"

input string InpTradeSymbol      = "";       // empty = use the chart's own symbol
input ENUM_TIMEFRAMES InpRegimeTimeframe = PERIOD_M15;
input long   InpMagicNumber      = 990001;
input int    InpSwingDepth       = 3;
input int    InpMaxLookback      = 50;
input int    InpSharedWindowBars = 250;      // shared OHLC/ATR window for all strategy evaluations

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

   PrintFormat("ThembaEA: initialized for '%s' on %s. JOURNAL-ONLY MODE — no order will "
               "ever be submitted by this build (TASK-025 scope).", g_symbol,
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

   // Safe by construction: only ever acts on this EA's own magic number,
   // and this build never opens a position under that magic — a no-op
   // in practice until a future task adds order submission.
   if(ICM_ShouldExecuteIntradayClose())
     {
      string closeReasons[];
      ICM_ExecuteIntradayClose(InpMagicNumber, closeReasons);
     }
  }

//+------------------------------------------------------------------+
//| Classifies the regime once, reads the shared OHLC/ATR window once,   |
//| computes structure once, evaluates all five strategies against that   |
//| SAME data, routes, resolves, and journals the outcome — no order       |
//| is ever submitted (see file header).                                   |
//+------------------------------------------------------------------+
void EvaluateAndJournal()
  {
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
   decision.ea_version = "0.1-task025-journal-only";

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
      PrintFormat("ThembaEA: decision = %s %s via %s (%s), score=%.2f — JOURNAL ONLY, "
                  "no order submitted.", decision.direction, g_symbol, decision.strategy,
                  decision.setup, decision.score);
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
