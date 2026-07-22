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
#include "../Include/ThembaEA/Risk/CooldownManager.mqh"
#include "../Include/ThembaEA/Journal/DecisionJournal.mqh"
#include "../Include/ThembaEA/Execution/IntradayCloseManager.mqh"
#include "../Include/ThembaEA/Execution/OrderManager.mqh"
#include "../Include/ThembaEA/Execution/IntentManager.mqh"
#include "../Include/ThembaEA/Execution/ExitOrchestrator.mqh"
#include "../Include/ThembaEA/Execution/AsyncFillCorrelator.mqh"
#include "../Include/ThembaEA/Market/RegimeGateComposer.mqh"
#include "../Include/ThembaEA/Market/IntradayModeRouter.mqh"
#include "../Include/ThembaEA/Market/SessionManager.mqh"
#include "../Include/ThembaEA/News/NewsManager.mqh"
#include "../Include/ThembaEA/News/MT5CalendarProvider.mqh"
#include "../Include/ThembaEA/News/NullNewsProvider.mqh"
#include "../Include/ThembaEA/News/FairEconomyNewsProvider.mqh"

//+------------------------------------------------------------------+
//| TASK-034/TASK-040 — live news-provider selection. This input picks     |
//| WHICH real-market provider to use (MT5's native calendar or the           |
//| FairEconomy feed) when this EA is running on a metal/forex symbol.          |
//| It no longer decides WHETHER to apply macro news filtering at all --          |
//| ResolveNewsBlackout() now overrides this to NullNewsProvider semantics          |
//| automatically whenever IntradayModeRouter.mqh's market_family                    |
//| classifier reports MARKET_FAMILY_SYNTHETIC_INDEX, per PROJECT_RULES.md              |
//| rule 8 — this used to be an explicit, operator-set stand-in for a                    |
//| missing classifier (TASK-034's original note); TASK-040 built that                     |
//| classifier, so the override is now automatic, not manual.                                |
//+------------------------------------------------------------------+
enum ENUM_NEWS_PROVIDER_SOURCE
  {
   NEWS_PROVIDER_MT5_CALENDAR,
   NEWS_PROVIDER_FAIR_ECONOMY,
   NEWS_PROVIDER_NONE
  };

input string InpTradeSymbol      = "";       // empty = use the chart's own symbol
input ENUM_TIMEFRAMES InpRegimeTimeframe = PERIOD_M15;
input long   InpMagicNumber      = 990001;
input int    InpSwingDepth       = 3;
input int    InpMaxLookback      = 50;
input int    InpSharedWindowBars = 250;      // shared OHLC/ATR window for all strategy evaluations

input ENUM_NEWS_PROVIDER_SOURCE InpNewsProviderSource = NEWS_PROVIDER_MT5_CALENDAR; // see note above
input string InpNewsCurrency               = "USD"; // "" = all currencies
input int    InpNewsMinImportance          = 3;      // high-impact only, section 10 default
input int    InpNewsBlackoutBeforeMinutes  = 15;
input int    InpNewsBlackoutAfterMinutes   = 15;
input int    InpNewsMaxExtensionMinutes    = 60;
input double InpMaxSpreadAtrMultiple       = 3.0;    // shared: untradeable-spread gate AND
                                                       // news post-event spread-normalization check
input double InpMinLiquidityTicksPerBar    = 5.0;
input int    InpLiquidityAvgBars           = 20;
input int    InpHysteresisRequiredBars     = 2;
input int    InpCooldownMinutes            = 90;     // TASK-034: three-loss-per-symbol cooldown

// TASK-040 (seventh-round rewrite): TASK-002_PHASE2_SPECIFICATION.md section 1's own
// canonical intraday-mode formula defaults.
input int    InpModePersistenceBars        = 20;     // regime-persistence component window
input double InpMinDayTradeSessionMinutes  = 90.0;    // session-time-remaining floor
input int    InpModeHysteresisEvaluations  = 2;       // see IntradayModeRouter.mqh's own stated
                                                        // M1-bar-vs-evaluation-cadence deviation
input double InpMinDayTradeR               = 1.0;     // stage-4 post-hoc consistency check
input double InpMaxScalpR                  = 2.0;     // stage-4 post-hoc consistency check

// TASK-041 (exit-engine wiring, partial scope -- see ExitOrchestrator.mqh's own header):
input double InpBreakEvenMinR              = 0.5;
input double InpTrailBufferAtrMultiple     = 0.3;
input double InpAtrTrailMultiple           = 2.0;
input int    InpTrailStaleBars             = 15;
input double InpScalpMaxMinutes            = 60.0;
input double InpTimeStopMinR               = 0.3;
input double InpProfitLockTriggerPercent   = 70.0;
input double InpProfitLockKeepPercent      = 50.0;
input double InpProfitLockMinKeepPercent   = 30.0;
input bool   InpTimeStopUsesScalpMode      = true; // TASK-041: stand-in policy applied to EVERY
                                                     // position this EA manages -- which time-stop
                                                     // duration ceiling (InpScalpMaxMinutes vs
                                                     // remaining-session-time) applies. Until
                                                     // intraday_mode (TASK-040) is captured
                                                     // per-position at entry time and threaded
                                                     // through to exit management end-to-end (a
                                                     // further, explicitly named follow-up), the
                                                     // operator sets this once per deployment,
                                                     // matching how InpNewsProviderSource stood in
                                                     // for market_family before TASK-040 shipped it.

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

CMarketData             g_md;
CSymbolProfile          g_profile;
string                  g_symbol;
datetime                g_last_evaluated_bar_time = 0;
SRegimeHysteresisState  g_hysteresis_state;
SModeState              g_mode_state; // TASK-040 (seventh-round rewrite): canonical mode formula's own state
ENUM_MARKET_FAMILY      g_market_family = MARKET_FAMILY_UNKNOWN;
long                    g_signal_counter = 0; // TASK-036: in-process counter feeding signal_id

int OnInit()
  {
   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 3): the input comment claims InpRiskPercentTarget/InpRiskCapPercent
   // enforce both per-trade and total-open risk, but nothing previously
   // validated that the target actually stays within the cap, or that
   // either value is even positive -- a misconfigured target exceeding
   // the cap had no gate to catch it before OM_CalculateVolume's own
   // now-added cap check (which only fires per-order, not at startup).
   if(InpRiskPercentTarget <= 0.0 || InpRiskCapPercent <= 0.0 ||
      InpRiskPercentTarget > InpRiskCapPercent)
     {
      PrintFormat("ThembaEA: invalid risk configuration -- InpRiskPercentTarget=%.4f, "
                  "InpRiskCapPercent=%.4f. Both must be positive and "
                  "InpRiskPercentTarget must not exceed InpRiskCapPercent. Refusing to run.",
                  InpRiskPercentTarget, InpRiskCapPercent);
      return INIT_FAILED;
     }

   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 3): TASK-002_PHASE2_SPECIFICATION.md requires this EA refuse to run
   // on a hedging-mode account (its own no-add-on/no-concurrent-position
   // rule and the single-position-per-symbol+magic risk model both assume
   // netting; a hedging account can hold simultaneous opposing positions
   // under the same symbol+magic, defeating that assumption entirely).**
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) ==
      ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("ThembaEA: this account is in HEDGING margin mode -- this EA's risk model assumes "
            "netting (one position per symbol+magic). Refusing to run.");
      return INIT_FAILED;
     }

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

   MRE_InitHysteresisState(g_hysteresis_state);
   IMR_InitModeState(g_mode_state);
   FEP_InvalidateCache(); // TASK-034: force a fresh FairEconomy fetch this session, not a stale one

   // TASK-040: classify market_family once at startup (this EA instance
   // trades exactly one symbol for its whole lifetime) via the broker's
   // own curated SYMBOL_PATH -- see IntradayModeRouter.mqh's own header
   // for why this differs from a ticker-name heuristic.
   g_market_family = IMR_ClassifyMarketFamily(g_symbol);
   PrintFormat("ThembaEA: market_family classified as %s for '%s' (SYMBOL_PATH='%s').",
               IMR_MarketFamilyToString(g_market_family), g_symbol,
               SymbolInfoString(g_symbol, SYMBOL_PATH));

   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 5): NEWS_PROVIDER_NONE returns "no blackout" unconditionally --
   // PROJECT_RULES.md's macro-news-filter requirement for metals/forex is
   // mandatory, not an operator preference (unlike the synthetic-index
   // case, where NullNewsProvider semantics are the CORRECT behavior, not
   // a bypass). Refuse to run rather than silently let an operator disable
   // a mandatory control by selecting NONE on a metal/forex symbol.**
   if(InpNewsProviderSource == NEWS_PROVIDER_NONE &&
      (g_market_family == MARKET_FAMILY_METAL || g_market_family == MARKET_FAMILY_FOREX))
     {
      PrintFormat("ThembaEA: InpNewsProviderSource=NEWS_PROVIDER_NONE is not permitted on a "
                  "%s symbol ('%s') -- the macro news-blackout filter is mandatory for metals/"
                  "forex, not an operator preference. Select MT5_CALENDAR or FAIR_ECONOMY. "
                  "Refusing to run.", IMR_MarketFamilyToString(g_market_family), g_symbol);
      return INIT_FAILED;
     }

   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 1): the create-if-absent bootstrap for this symbol+magic's durable-
   // intent lock now runs exactly once here, before any order-submission
   // logic can ever call IM_BeginIntent — see IntentManager.mqh's own
   // header for why this closes the practical multi-instance creation
   // race that living inside IM_BeginIntent's own hot path could not.**
   IM_EnsureInitialized(g_symbol, InpMagicNumber);

   // TASK-034: reconcile any durable-intent record orphaned by a crash/restart between
   // "about to submit" and "confirmed filled or rejected" — before resuming normal operation.
   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 1):
   // a matching PENDING ORDER (accepted at the broker, not yet filled/
   // cancelled) now leaves the intent deliberately ACTIVE rather than
   // clearing it and resuming as if nothing were outstanding.**
   bool orphaned_intent_was_filled, orphaned_intent_still_pending;
   if(IM_ReconcileOnRestart(g_symbol, InpMagicNumber, orphaned_intent_was_filled,
                             orphaned_intent_still_pending))
     {
      string reconcile_outcome;
      if(orphaned_intent_still_pending)
         reconcile_outcome = "a pending order still exists at the broker — intent left ACTIVE "
                              "until OnTradeTransaction observes its terminal outcome";
      else if(orphaned_intent_was_filled)
         reconcile_outcome = "a matching position exists (order had filled)";
      else
         reconcile_outcome = "no matching position or pending order exists (order never filled)";
      PrintFormat("ThembaEA: reconciled an orphaned durable-intent record on restart for '%s' "
                  "magic %I64d — %s.", g_symbol, InpMagicNumber, reconcile_outcome);
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

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding    |
//| 2): this used to APPEND a synthetic STradeDecision journal row for an       |
//| async fill/cancellation outcome. The review found that record was            |
//| schema-invalid on multiple axes at once -- market_family/intraday_mode/       |
//| regime left empty (the Python schema requires a recognized enum value           |
//| for each), direction="NONE" combined with a real order_id confusing the          |
//| outcome join's direction/is_long check, and the reused signal_id                    |
//| colliding with the original decision's own journal-uniqueness                          |
//| expectations. Rather than patch each individual defect (the review's own                 |
//| own suggestion is a genuinely separate submission/order/fill EVENT                          |
//| schema, distinct from STradeDecision, which is real, larger design work                        |
//| this fix does not attempt to invent under review pressure), this now                             |
//| logs the resolution for operator visibility ONLY -- it does not write a                            |
//| journal row claiming to be a trade decision. The safety-critical half of                             |
//| async correlation (never submitting a duplicate order) does not depend                                 |
//| on any journal write at all -- it is IntentManager.mqh's own durable                                     |
//| intent flag, cleared here on definitive resolution. A real, schema-                                        |
//| correct async event record remains a genuine, named follow-up.**              |
//+------------------------------------------------------------------+
void LogAsyncFillResolution(const string original_signal_id, const bool filled,
                             const ulong resolved_position_id, const string outcome_note)
  {
   if(filled)
      PrintFormat("ThembaEA: async fill resolved for signal_id=%s -- position_id=%I64u (%s).",
                  original_signal_id, resolved_position_id, outcome_note);
   else
      PrintFormat("ThembaEA: async order resolved WITHOUT filling for signal_id=%s (%s).",
                  original_signal_id, outcome_note);
  }

//+------------------------------------------------------------------+
//| Feeds CooldownManager.mqh/PositionStateTracker.mqh on a confirmed     |
//| closing deal (TASK-034/TASK-041), and resolves TASK-036's                |
//| asynchronous fill correlation: a DEAL_ENTRY_IN deal whose order matches       |
//| a pending PLACED submission confirms the async fill; an order that            |
//| moves to history in any state OTHER than FILLED while still pending              |
//| means it was cancelled/expired/rejected without ever filling — either               |
//| way, this appends a correlated follow-up journal record rather than                   |
//| leaving the original decision's null order_id/deal_id unexplained.                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(!HistoryDealSelect(trans.deal))
         return;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
        {
         if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagicNumber &&
            HistoryDealGetString(trans.deal, DEAL_SYMBOL) == g_symbol)
           {
            double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                         HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                         HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
            CDM_RecordClosedTrade(g_symbol, InpMagicNumber, pnl, TimeCurrent(), InpCooldownMinutes);

            // TASK-041: no partial-close functionality exists anywhere in
            // this project yet, so a closing deal always means the
            // position is genuinely gone, never a still-open remainder.
            ulong closed_position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
            if(closed_position_id != 0)
               PST_Clear(closed_position_id);
           }
         return;
        }

      if(entry == DEAL_ENTRY_IN)
        {
         string pending_signal_id;
         int pending_index;
         if(AFC_FindPending(trans.order, pending_signal_id, pending_index))
           {
            ulong resolved_position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
            AFC_RemovePending(pending_index);
            // Definitive terminal resolution -- safe to clear the durable
            // intent now (see AttemptOrderSubmission's own step 7 comment
            // for why it was deliberately left active until this point).
            IM_ClearIntent(g_symbol, InpMagicNumber);
            LogAsyncFillResolution(pending_signal_id, true, resolved_position_id,
                                    "async_fill_confirmed");
           }
        }
      return;
     }

   if(trans.type == TRADE_TRANSACTION_HISTORY_ADD)
     {
      string pending_signal_id;
      int pending_index;
      if(AFC_FindPending(trans.order, pending_signal_id, pending_index))
        {
         ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(trans.order, ORDER_STATE);
         if(state != ORDER_STATE_FILLED)
           {
            AFC_RemovePending(pending_index);
            IM_ClearIntent(g_symbol, InpMagicNumber); // cancelled/expired/rejected -- terminal
            LogAsyncFillResolution(pending_signal_id, false, 0,
                                    StringFormat("async_order_never_filled_state_%s",
                                                  EnumToString(state)));
           }
        }
      return;
     }
  }

void OnDeinit(const int reason)
  {
   PrintFormat("ThembaEA: deinitialized, reason=%d.", reason);
  }

void OnTick()
  {
   // **Reordered, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 8): mandatory boundary protection now runs FIRST, on EVERY tick, ahead
   // of any entry evaluation or position management -- previously it ran
   // last and only on the first tick of a new bar (so the advertised
   // "retry on the next tick" was actually "retry once per bar"). This is a
   // pure function of the current server clock (no per-day flag of its own
   // to lose), scoped strictly to this EA's own magic number. With
   // InpEnableOrderSubmission=false this remains a no-op in practice
   // (nothing is ever opened under this magic); with it true, this is this
   // EA's real end-of-day exposure close, and it now retries every tick
   // until ICM_ExecuteIntradayClose reports a fully broker-confirmed
   // success (see IntradayCloseManager.mqh's own P0 finding 8 fix).**
   if(ICM_ShouldExecuteIntradayClose())
     {
      string closeReasons[];
      ICM_ExecuteIntradayClose(InpMagicNumber, closeReasons);
     }

   // **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding 8):
   // a persistent post-boundary entry lock. SN_IsPastIntradayBoundary() is a
   // pure function of the current server clock, so this needs no
   // restart-durable flag: it is true on every tick past today's boundary
   // regardless of whether the EA (re)started mid-day, and it naturally
   // resets to false at the next server midnight without any date-tracking
   // of its own. This closes the gap where a fully successful close (which
   // suppresses further CLOSE attempts for the rest of the day via
   // g_icm_close_done_today) left no gate blocking a later bar's NEW entry
   // after the boundary had already passed.**
   bool past_intraday_boundary = SN_IsPastIntradayBoundary();

   // **Reordered, 2026-07-22 (Codex review finding, seventh round, P0
   // finding 8): tick-sensitive exit management (structure/ATR trailing,
   // profit-lock, time stop) now runs on EVERY tick, not gated behind the
   // once-per-completed-bar check below -- ExitOrchestrator.mqh's own
   // header advertises a per-tick decision, but its only live caller
   // previously ran once per completed bar (since OnTick returned early on
   // every other tick), losing intrabar responsiveness entirely.
   // 'is_new_completed_bar' still gates the bar-count-based staleness clock
   // inside EO_EvaluatePosition itself -- only the CALL cadence changed.**
   bool is_new_completed_bar = false;
   datetime current_bar_time;
   if(g_md.GetTime(0, current_bar_time) && current_bar_time != g_last_evaluated_bar_time)
     {
      is_new_completed_bar = true;
      g_last_evaluated_bar_time = current_bar_time;
     }

   ManageOpenPositions(is_new_completed_bar);

   // New-entry evaluation stays on this pipeline's own once-per-completed-bar
   // decision cadence. AttemptOrderSubmission (called from within
   // EvaluateAndJournal's own decision path) additionally refuses any new
   // entry once past_intraday_boundary is true, regardless of whether
   // today's close operation above has itself fully succeeded yet.
   if(is_new_completed_bar)
      EvaluateAndJournal(past_intraday_boundary);
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
//| TASK-034 — average tick (proxy for real-trade) volume per bar over     |
//| 'bars' completed bars, fed to MRE_IsUntradeableSpreadOrLiquidity's         |
//| liquidity check. Bars with an unreadable tick-volume value are            |
//| skipped rather than treated as zero (a data-read failure should not          |
//| masquerade as a genuine liquidity drought); returns 0.0 if none of the         |
//| requested bars were readable at all.                                              |
//+------------------------------------------------------------------+
double ComputeAvgTicksPerBar(const int bars)
  {
   long total = 0;
   int  valid = 0;
   for(int i = 0; i < bars; i++)
     {
      long v;
      if(g_md.GetTickVolume(i, v))
        {
         total += v;
         valid++;
        }
     }
   if(valid == 0)
      return 0.0;
   return (double)total / (double)valid;
  }

//+------------------------------------------------------------------+
//| **Rewritten, 2026-07-22 (Codex review finding, seventh round, P0       |
//| finding 6):** replaces the previous ComputeCurrentRangeRatio (a single-       |
//| bar-vs-trailing-average proxy, no longer called anywhere) with a direct          |
//| port of TASK-002 section 1's own component-3 definition: "today's session          |
//| range so far divided by the InpRegimeTF ATR." Scans back from the most               |
//| recent completed bar (index 0) until crossing today's server-day                        |
//| boundary, tracking the running high/low over that span. Returns 0.0 if                     |
//| no bar this session is available yet (e.g. right at a fresh day's open) or                   |
//| current_atr is non-positive.                                                                     |
//+------------------------------------------------------------------+
double ComputeTodaySessionRangeAtrMultiple(const double &highs[], const double &lows[],
                                            const double current_atr)
  {
   if(current_atr <= 0.0)
      return 0.0;

   datetime day_start = SN_CurrentDailyBoundary();
   double today_high = -DBL_MAX;
   double today_low = DBL_MAX;
   bool any_bar_today = false;

   int n = ArraySize(highs);
   for(int i = 0; i < n; i++)
     {
      datetime bar_time;
      if(!g_md.GetTime(i, bar_time))
         break;
      if(bar_time < day_start)
         break; // bars are newest-first; once we cross the boundary, stop scanning

      if(highs[i] > today_high) today_high = highs[i];
      if(lows[i] < today_low) today_low = lows[i];
      any_bar_today = true;
     }

   if(!any_bar_today)
      return 0.0;

   return (today_high - today_low) / current_atr;
  }

//+------------------------------------------------------------------+
//| TASK-034 — resolves whether NEWS_BLACKOUT is currently active, per    |
//| InpNewsProviderSource (see that input's own header comment for why        |
//| this is a manual, explicitly-named stand-in for the still-unbuilt            |
//| market_family classifier, not an automatic per-symbol routing). Both          |
//| live providers fail CLOSED (an unreachable/failed feed is treated as           |
//| an active blackout, per TASK-034_LIVE_SAFETY_WIRING.md Specification            |
//| item 4) — 'triggering_event_id_out' is set to a distinguishable                    |
//| sentinel in that case so the journal shows WHY the blackout fired.                    |
//+------------------------------------------------------------------+
bool ResolveNewsBlackout(const double current_atr, string &triggering_event_id_out)
  {
   triggering_event_id_out = "";

   // TASK-040: automatic override, regardless of InpNewsProviderSource --
   // PROJECT_RULES.md rule 8 ("macroeconomic news filters apply to
   // metals, not Deriv synthetic indices") is not an operator preference,
   // it is a correctness rule (synthetic indices are algorithm-generated
   // and are not driven by real-world macro news at all, per
   // 00_MASTER_PROMPT_FOR_CLAUDE.md), so a real market_family
   // classification now enforces it even if the operator left
   // InpNewsProviderSource pointed at a real-market provider by mistake.
   // This closes TASK-034's previously-blocked synthetic-bypass
   // acceptance item now that IntradayModeRouter.mqh exists.
   if(g_market_family == MARKET_FAMILY_SYNTHETIC_INDEX)
     {
      SNewsEvent none_events[];
      NNP_FetchEvents(none_events);
      return false;
     }

   if(InpNewsProviderSource == NEWS_PROVIDER_NONE)
     {
      // Mirrors NullNewsProvider.mqh exactly: always zero events, never a blackout.
      SNewsEvent none_events[];
      NNP_FetchEvents(none_events);
      return false;
     }

   if(InpNewsProviderSource == NEWS_PROVIDER_FAIR_ECONOMY)
     {
      bool feed_unavailable;
      bool blackout = FEP_IsInBlackoutNow(g_symbol, InpNewsCurrency, InpNewsMinImportance,
                                           InpNewsBlackoutBeforeMinutes,
                                           InpNewsBlackoutAfterMinutes, InpNewsMaxExtensionMinutes,
                                           InpMaxSpreadAtrMultiple, current_atr,
                                           triggering_event_id_out, feed_unavailable);
      if(feed_unavailable)
        {
         triggering_event_id_out = "feed_unavailable_fail_closed";
         return true;
        }
      return blackout;
     }

   // NEWS_PROVIDER_MT5_CALENDAR (default).
   int fetch_result;
   bool blackout = MTC_IsInBlackoutNow(g_symbol, InpNewsCurrency, InpNewsMinImportance,
                                        InpNewsBlackoutBeforeMinutes, InpNewsBlackoutAfterMinutes,
                                        InpNewsMaxExtensionMinutes, InpMaxSpreadAtrMultiple,
                                        current_atr, triggering_event_id_out, fetch_result);
   if(fetch_result < 0)
     {
      triggering_event_id_out = "feed_unavailable_fail_closed";
      return true;
     }
   return blackout;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding    |
//| 3):** sums risk_cash across every CURRENTLY OPEN position matching this      |
//| EA's own InpMagicNumber, on ANY symbol -- per                                   |
//| TASK-002_PHASE2_SPECIFICATION.md section 8's own stated scope ("the 1%             |
//| per-trade and 1% total-open-risk caps are scoped to this EA's own                     |
//| managed exposure (own magic number)... no authority or reliable                          |
//| visibility contract over other EAs'/manual positions"). This needs no                       |
//| custom cross-instance ledger -- PositionsTotal()/PositionGetTicket already                    |
//| enumerate every position on the account regardless of which chart/symbol                        |
//| is asking, so a single instance can already see every position sharing its                         |
//| own magic number on a different symbol.                                                                |
//|                                                                    |
//| A position with no stop (POSITION_SL == 0) is skipped, not counted as        |
//| zero risk -- this project's no-SL fallback risk formula                          |
//| (`risk_cash_no_stop`, TASK-002 section 8) is a separate, not-yet-built              |
//| path; skipping (rather than silently treating as zero) is a stated,                    |
//| bounded limitation of this fix, not a claim that a stopless position is                    |
//| risk-free.                                                                                     |
//+------------------------------------------------------------------+
double ComputeOwnMagicOpenRiskCash()
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      double sl = PositionGetDouble(POSITION_SL);
      if(sl == 0.0)
         continue; // no-SL fallback formula not yet built -- see header comment

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      bool pos_is_long = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      double loss_distance = pos_is_long ? MathMax(0.0, entry - sl) : MathMax(0.0, sl - entry);
      if(loss_distance <= 0.0)
         continue;

      CSymbolProfile pos_profile;
      if(!pos_profile.Load(pos_symbol))
         continue;

      double risk_cash;
      if(RM_ComputeRiskCash(pos_profile, loss_distance, volume, risk_cash))
         total += risk_cash;
     }
   return total;
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
//| 'gate_reasons' (TASK-034) is the regime/cooldown gate journal built        |
//| by EvaluateAndJournal — seeded into 'passed' first so it is never          |
//| lost regardless of which step below eventually rejects or succeeds.          |
//|                                                                    |
//| Gating sequence, in order (matches TASK-027_WIRE_ORDER_MANAGER.md's   |
//| Specification section, extended by TASK-034):                          |
//|  -1. Persistent post-intraday-boundary entry lock (seventh-round P0        |
//|      finding 8).                                                              |
//|  0. Three-loss-per-symbol cooldown (TASK-034, CooldownManager.mqh).       |
//|  1. No-add-on/no-concurrent-position rule (section 8).                     |
//|  2. Daily/weekly loss caps, account-wide measurement (section 8).            |
//|  3. Drawdown-based risk reduction, never increase (section 8).                |
//|  4. Stop-distance floor/cap preflight (section 8, RiskManager.mqh).             |
//|  5. Position sizing incl. broker-minimum-vs-cap rejection (OrderManager).        |
//|  5b. Own-magic total-open-risk cap (seventh-round P0 finding 3).                   |
//|  6. OrderCalcProfit cross-check (RISK_POLICY.md blanket rule).                    |
//|  7. Durable-intent-guarded real order submission (TASK-034, OrderManager).          |
//+------------------------------------------------------------------+
void AttemptOrderSubmission(STradeDecision &decision, const SConflictResult &resolution,
                             const double atr_current, const string &gate_reasons[],
                             const bool past_intraday_boundary)
  {
   string passed[];
   string rejected[];
   for(int gi = 0; gi < ArraySize(gate_reasons); gi++)
      AppendReason(passed, gate_reasons[gi]);

   //--- -1. Persistent post-intraday-boundary entry lock (Codex review -----
   //--- finding, seventh round, P0 finding 8): a fully successful boundary --
   //--- close only suppresses further CLOSE attempts for the rest of the ----
   //--- day (IntradayCloseManager.mqh's own guard) -- it does not, by --------
   //--- itself, stop a LATER bar from opening new same-day exposure. This ----
   //--- check is a pure function of the current server clock (no in-memory --
   //--- flag of its own to lose across a restart), so it blocks every entry ---
   //--- attempt from the moment the boundary passes until the next server -----
   //--- midnight, every day, unconditionally. -----------------------------------
   if(past_intraday_boundary)
     {
      AppendReason(rejected, "past_intraday_boundary_no_new_entries");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   //--- 0. Three-loss-per-symbol cooldown (TASK-034) ----------------------
   datetime cooldown_until;
   if(CDM_IsInCooldown(g_symbol, InpMagicNumber, TimeCurrent(), cooldown_until))
     {
      AppendReason(rejected, StringFormat("cooldown_active_until_%I64d", (long)cooldown_until));
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

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

   //--- 5b. Own-magic total-open-risk cap (Codex review finding, seventh --
   //--- round, P0 finding 3) -------------------------------------------------
   // TASK-002_PHASE2_SPECIFICATION.md section 8: "total_open_risk_pct = 100 x
   // Sum risk_cash_i / current_equity", scoped to this EA's OWN magic number
   // across every symbol it manages (not other EAs'/manual positions, which
   // this engine has no visibility contract over) -- checked against the
   // SAME InpRiskCapPercent value the per-trade check above already uses,
   // matching the spec's own stated "hard cap 1.00% per trade, 1.00% total
   // open risk" (both caps share one number in this project's design).
   double existing_open_risk_cash = ComputeOwnMagicOpenRiskCash();
   double total_open_risk_percent = 100.0 * (existing_open_risk_cash + sizing.risk_cash_actual) /
                                     equity;
   if(total_open_risk_percent > InpRiskCapPercent + 1e-6)
     {
      AppendReason(rejected, StringFormat(
         "total_open_risk_cap_exceeded_%.4fpct_cap_%.4fpct", total_open_risk_percent,
         InpRiskCapPercent));
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   AppendReason(passed, StringFormat("total_open_risk_cap_clear_%.4fpct", total_open_risk_percent));

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

   //--- 7. Durable-intent-guarded real order submission (TASK-034) --------
   if(!IM_BeginIntent(g_symbol, InpMagicNumber, is_long, sizing.volume, TimeCurrent()))
     {
      // An intent is already active — a prior submission on this symbol+magic
      // has not yet been confirmed filled/rejected. Refuse to submit a
      // second order rather than risk a duplicate position.
      AppendReason(rejected, "intent_already_active_refusing_duplicate_submission");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   string comment = StringFormat("Themba_%s", decision.strategy);
   if(StringLen(comment) > 31)
      comment = StringSubstr(comment, 0, 31); // MT5 order-comment length limit

   SOrderOpenResult open_result;
   bool opened = OM_OpenPosition(g_symbol, is_long, sizing.volume, final_stop,
                                   resolution.winner.target_price, InpMagicNumber, comment,
                                   open_result);
   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 1):
   // the intent is CONFIRMED-terminal only when the order was rejected
   // outright, or a synchronous fill resolved a real position_id. A
   // TRADE_RETCODE_PLACED result whose position could not be resolved
   // synchronously is NOT terminal -- clearing the intent here (the
   // previous behavior) discarded the one durable, restart-safe record of
   // an order that may still be live at the broker. The intent now stays
   // ACTIVE until OnTradeTransaction observes the order's actual terminal
   // outcome (fill confirmed, or cancelled/expired).
   if(!opened)
     {
      IM_ClearIntent(g_symbol, InpMagicNumber); // rejected outright -- definitively terminal
      AppendReason(rejected, "order_" + open_result.rejection_reason);
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   if(open_result.position_id != 0)
      IM_ClearIntent(g_symbol, InpMagicNumber); // synchronous fill confirmed -- definitively terminal

   // Success — reflect the ACTUAL submitted stop back into the journal
   // record (a floor widening in step 4 may have moved it from the
   // strategy's originally proposed stop).
   decision.stop = final_stop;
   decision.risk_percent = 100.0 * sizing.risk_cash_actual / equity;
   // TASK-036: order_id is the DURABLE position_id (POSITION_IDENTIFIER),
   // never position_ticket -- see OrderManager.mqh's own SOrderOpenResult
   // comment for why. "" (JSON null) if the position could not be resolved
   // synchronously -- the TRADE_RETCODE_PLACED-not-yet-filled case, handled
   // below.
   //
   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 2):
   // decision.deal_id is deliberately left unset (null) here, not populated
   // from open_result.deal_ticket (the OPENING deal). Export_TradeHistory.mq5
   // exports one row per CLOSING deal only (its own deal_id column is a
   // closing-deal ticket), so a journal deal_id populated from the OPENING
   // deal can never be a member of any real trade's exported deal_id set --
   // join_signal_to_outcome.py's own membership check
   // (journal deal_id must be among a matched position's fill deal_ids)
   // would then reject EVERY ordinary, legitimately-filled position as a
   // conflict. order_id (position_id) remains the correct, sole join key;
   // a real per-fill deal_id contract (open vs. close, or a proper event
   // schema per the review's own suggestion) is a genuine follow-up, not
   // silently faked here.**
   if(open_result.position_id != 0)
      decision.order_id = IntegerToString((long)open_result.position_id);

   AppendReason(passed, StringFormat(
      "order_submitted_ticket_%I64u_position_id_%I64u_volume_%.2f_fill_%.5f",
      open_result.position_ticket, open_result.position_id, sizing.volume,
      open_result.fill_price));
   PrintFormat("ThembaEA: *** ORDER SUBMITTED *** %s %s volume=%.2f ticket=%I64u "
               "position_id=%I64u fill=%.5f stop=%.5f risk_pct=%.4f", decision.direction,
               g_symbol, sizing.volume, open_result.position_ticket, open_result.position_id,
               open_result.fill_price, final_stop, decision.risk_percent);

   decision.reasons_passed_json = BuildJsonStringArray(passed);
   decision.reasons_rejected_json = BuildJsonStringArray(rejected);

   // TASK-036 Specification item 4: an accepted-but-not-yet-resolved
   // position (retcode PLACED, position_id still 0) cannot be journaled
   // with a real order_id/deal_id yet -- register it for later
   // correlation so OnTradeTransaction can append a follow-up record once
   // the async fill (or cancellation/expiry) actually arrives, rather
   // than leaving this record's null order_id/deal_id unexplained forever.
   if(open_result.position_id == 0 && open_result.order_ticket != 0)
      AFC_AddPending(open_result.order_ticket, decision.signal_id);
  }

//+------------------------------------------------------------------+
//| TASK-041 — manages every OPEN position under this EA's own magic on   |
//| 'g_symbol', once per completed bar: composes break-even, structure/      |
//| ATR trailing, time stop, and profit-lock via ExitOrchestrator.mqh (see       |
//| that module's own header for this task's explicitly-approved partial          |
//| scope). Independent of EvaluateAndJournal's own regime-classification            |
//| gates -- an existing open position must still be protected even on a a             |
//| bar where a NEW entry decision could not be evaluated.                                |
//|                                                                    |
//| 'is_new_completed_bar' (Codex review finding, seventh round, P0 finding    |
//| 8): now caller-supplied instead of hardcoded true -- OnTick calls this        |
//| function on EVERY tick (not just the first tick of a new bar) so trailing/       |
//| profit-lock/time-stop react intrabar; only the bar-count-based staleness           |
//| clock inside EO_EvaluatePosition still advances once per completed bar.               |
//+------------------------------------------------------------------+
void ManageOpenPositions(const bool is_new_completed_bar)
  {
   double atr_current;
   if(!g_md.GetATR(0, atr_current, 14))
      return; // cannot manage without a live ATR read this bar

   int window = InpSwingDepth * 2 + InpMaxLookback + 5;
   if(!g_md.HasBars(window))
      return;
   double highs[], lows[];
   ArrayResize(highs, window);
   ArrayResize(lows, window);
   for(int i = 0; i < window; i++)
      if(!g_md.GetHigh(i, highs[i]) || !g_md.GetLow(i, lows[i]))
         return;

   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 8):
   // a session-calendar lookup failure must NOT be silently coerced to
   // remaining ratio 0.0 -- for a day-trade-mode position that reads as
   // "duration exceeded" and could force an unintended close purely because
   // of a data hiccup, not a real end of session. 'session_ratio_known' is
   // now threaded through to EO_EvaluatePosition/EM_ShouldTimeStop so an
   // unknown session state simply cannot trigger the duration-based time
   // stop at all (the intraday boundary close remains the real safety net,
   // since it depends only on the server clock, never the session
   // calendar).**
   double session_remaining_ratio, session_remaining_minutes_unused;
   bool session_ratio_known = SN_GetSessionMinutesRemaining(g_symbol, session_remaining_ratio,
                                                              session_remaining_minutes_unused);
   if(!session_ratio_known)
      session_remaining_ratio = 0.0;

   SExitConfig cfg;
   cfg.break_even_min_r = InpBreakEvenMinR;
   cfg.trail_buffer_atr_multiple = InpTrailBufferAtrMultiple;
   cfg.atr_trail_multiple = InpAtrTrailMultiple;
   cfg.trail_stale_bars = InpTrailStaleBars;
   cfg.scalp_max_minutes = InpScalpMaxMinutes;
   cfg.time_stop_min_r = InpTimeStopMinR;
   cfg.profit_lock_trigger_percent = InpProfitLockTriggerPercent;
   cfg.profit_lock_keep_percent = InpProfitLockKeepPercent;
   cfg.stop_modify_tolerance = g_profile.point * 2.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;

      ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      bool is_long = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_stop = PositionGetDouble(POSITION_SL);
      double target_price = PositionGetDouble(POSITION_TP);
      double current_price = is_long ? SymbolInfoDouble(g_symbol, SYMBOL_BID)
                                       : SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      double elapsed_minutes = (double)(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME)) /
                                60.0;

      SPositionExitState state = PST_Load(position_id);
      if(state.initial_stop_price == 0.0)
         state.initial_stop_price = current_stop; // seed once, before any trailing occurs

      SExitDecision decision = EO_EvaluatePosition(
         is_long, entry_price, state.initial_stop_price, current_stop, current_price, target_price,
         atr_current, highs, lows, InpSwingDepth, InpMaxLookback, is_new_completed_bar,
         InpTimeStopUsesScalpMode, session_remaining_ratio, session_ratio_known, elapsed_minutes,
         cfg, state);

      PST_Save(position_id, state);

      if(decision.should_close)
        {
         string close_reason;
         bool closed = OM_ClosePosition(ticket, InpMagicNumber, close_reason);
         PrintFormat("ThembaEA: exit orchestrator CLOSE (%s) position_id=%I64u ticket=%I64u -> %s.",
                     decision.close_reason, position_id, ticket,
                     closed ? "closed" : ("FAILED: " + close_reason));
         if(closed)
            PST_Clear(position_id);
         continue;
        }

      if(decision.should_modify_stop)
        {
         SOrderModifyResult modify_result;
         bool modified = OM_ModifyStop(ticket, InpMagicNumber, decision.new_stop_price, modify_result);
         if(modified)
           {
            PrintFormat("ThembaEA: exit orchestrator trail stop position_id=%I64u ticket=%I64u "
                        "requested=%.5f actual=%.5f.", position_id, ticket, decision.new_stop_price,
                        modify_result.actual_sl);
            if(state.profit_lock_armed &&
               !EM_ProfitLockClearsMinFloor(is_long, entry_price, current_price,
                                             modify_result.actual_sl, InpProfitLockMinKeepPercent))
               PrintFormat("ThembaEA: WARNING partial profit-lock only -- position_id=%I64u actual "
                           "stop %.5f does not clear the %.2f%% min-keep floor (broker minimum-"
                           "stop-distance likely widened it).", position_id, modify_result.actual_sl,
                           InpProfitLockMinKeepPercent);
           }
         else
            PrintFormat("ThembaEA: exit orchestrator stop modify FAILED position_id=%I64u "
                        "ticket=%I64u requested=%.5f -> %s.", position_id, ticket,
                        decision.new_stop_price, modify_result.rejection_reason);
        }
     }
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding    |
//| 7):** on regime-classification or required-data-read failure,             |
//| EvaluateAndJournal previously returned before DJ_AppendDecision was ever      |
//| called at all, contradicting this EA's own "journal every bar" claim.          |
//| The approved behavior is a journaled transition-state record with zero            |
//| confidence and an immediate hysteresis bypass to TRANSITION_OR_UNCERTAIN             |
//| (so a subsequent good read does not have to fight through stale pending                |
//| hysteresis state left over from the failure bar).                                        |
//+------------------------------------------------------------------+
void JournalDataFailureDecision(const string failure_reason)
  {
   MRE_ApplyHysteresis(g_hysteresis_state, REGIME_TRANSITION_OR_UNCERTAIN, true,
                        InpHysteresisRequiredBars);

   g_signal_counter++;
   string signal_id = StringFormat("%s_%I64d_%I64d", g_symbol, (long)TimeCurrent(),
                                    g_signal_counter);

   STradeDecision decision = DJ_NewDecision();
   decision.signal_id = signal_id;
   decision.timestamp = DJ_ServerTimeToUtc(TimeCurrent());
   decision.symbol = g_symbol;
   decision.market_family = IMR_MarketFamilyToString(g_market_family);
   decision.intraday_mode = IMR_IntradayModeToString(INTRADAY_MODE_SCALP); // unknown -- conservative default
   decision.regime = EnumToString(REGIME_TRANSITION_OR_UNCERTAIN);
   decision.regime_confidence = 0.0;
   decision.direction = "NONE";
   decision.strategy = "NoTrade";
   decision.setup = "data_failure";
   decision.news_state = "CLEAR"; // unknown -- not evaluated this bar, never fabricate BLACKOUT
   decision.session_state = "SESSION_TIME_REMAINING_UNKNOWN";
   decision.ea_version = "1.01-task027-order-submission-optional";

   string reason_arr[];
   AppendReason(reason_arr, failure_reason);
   decision.reasons_rejected_json = BuildJsonStringArray(reason_arr);

   string journal_error;
   if(!DJ_AppendDecision(decision, journal_error))
      PrintFormat("ThembaEA: failed to journal a data-failure decision: %s", journal_error);
  }

//+------------------------------------------------------------------+
//| Classifies the regime once, reads the shared OHLC/ATR window once,   |
//| computes structure once, evaluates all five strategies against that   |
//| SAME data, routes, resolves, journals the outcome, and — only when     |
//| InpEnableOrderSubmission is true — attempts a fully risk-gated real     |
//| order submission for the winning candidate (see file header).          |
//|                                                                    |
//| 'past_intraday_boundary' (Codex review finding, seventh round, P0       |
//| finding 8): threaded through to AttemptOrderSubmission as a persistent   |
//| entry lock -- a decision can still be evaluated/journaled past the        |
//| boundary (this EA's own "journal every bar" invariant), but no new         |
//| order may be submitted once the intraday boundary has passed, regardless      |
//| of whether today's close operation has itself fully succeeded yet.             |
//+------------------------------------------------------------------+
void EvaluateAndJournal(const bool past_intraday_boundary)
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
      JournalDataFailureDecision("regime_classification_failed");
      return;
     }

   if(!g_md.HasBars(InpSharedWindowBars))
     {
      Print("ThembaEA: insufficient history for the shared evaluation window — skipping.");
      JournalDataFailureDecision("insufficient_shared_window_history");
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
         JournalDataFailureDecision("price_or_atr_read_failed");
         return;
        }
     }

   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 7):
   // MRE_ClassifyArray's own low_confidence_override (confidence < 0.5) was
   // computed but never consumed downstream -- a low-confidence trend/range/
   // expansion/compression read still traded exactly like a high-confidence
   // one. The approved spec requires TRANSITION_OR_UNCERTAIN routing
   // treatment below that threshold; substituting it here (before the gate
   // composer/strategy evaluation ever see the raw regime) makes
   // STR_RouteCandidates' own existing TRANSITION_OR_UNCERTAIN default case
   // (blocks every family) apply, with no separate routing logic needed.
   ENUM_MARKET_REGIME regime_for_gating = regime_read.low_confidence_override
                                           ? REGIME_TRANSITION_OR_UNCERTAIN
                                           : regime_read.regime;

   //--- TASK-034: compose the untradeable-spread/liquidity gate, the news-  --
   //--- blackout gate, and hysteresis into ONE effective regime, BEFORE any --
   //--- strategy evaluation or routing ever sees the raw classifier read — --
   //--- exactly the "all three gates composed in one place, not scattered" --
   //--- requirement (Specification item 3), avoiding the short-circuit-    --
   //--- skipping risk the task's own Risks section warns about.            --
   double current_spread = (double)SymbolInfoInteger(g_symbol, SYMBOL_SPREAD) *
                            SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double avg_ticks_per_bar = ComputeAvgTicksPerBar(InpLiquidityAvgBars);
   bool spread_liquidity_untradeable = MRE_IsUntradeableSpreadOrLiquidity(
      current_spread, atr_values[0], InpMaxSpreadAtrMultiple, avg_ticks_per_bar,
      InpMinLiquidityTicksPerBar);

   string news_event_id;
   bool news_blackout = ResolveNewsBlackout(atr_values[0], news_event_id);

   SRegimeGateResult gate_result = RGC_ComposeGates(g_hysteresis_state, regime_for_gating,
                                                     spread_liquidity_untradeable, news_blackout,
                                                     news_event_id, InpHysteresisRequiredBars);
   ENUM_MARKET_REGIME effective_regime = gate_result.effective_regime;

   // Journaled every bar regardless of decision outcome, per Specification
   // item 5 ("journal every gate decision... so Python-side analysis has
   // real data to validate against").
   string gate_reasons[];
   AppendReason(gate_reasons, "regime_raw_" + EnumToString(regime_read.regime));
   if(regime_read.low_confidence_override)
      AppendReason(gate_reasons, "low_confidence_override_forced_transition");
   AppendReason(gate_reasons, "regime_effective_" + EnumToString(effective_regime));
   if(gate_result.spread_liquidity_gate_active)
      AppendReason(gate_reasons, "gate_spread_liquidity_active");
   if(gate_result.news_gate_active)
      AppendReason(gate_reasons, "gate_news_active_event_" + gate_result.news_triggering_event_id);
   if(!gate_result.spread_liquidity_gate_active && !gate_result.news_gate_active)
      AppendReason(gate_reasons, "gate_clear");

   SMarketStructureState structure;
   MS_ComputeStructureArray(highs, lows, closes, InpSwingDepth, InpMaxLookback, structure);

   STradeCandidate candidates[5];

   // 1. SR Bounce
   SSRBounceSignal srSig;
   SRB_EvaluateArray(opens, highs, lows, closes, atr_values, InpSwingDepth, InpMaxLookback,
                      effective_regime, structure, 0.3, 2, 0.3, 5, srSig);
   candidates[0] = SS_FromSRBounce(srSig);

   // 2. SMC/ICT
   SSMCConfig smcCfg;
   smcCfg.depth = InpSwingDepth; smcCfg.max_lookback = InpMaxLookback;
   smcCfg.displacement_atr_multiple = 1.5; smcCfg.retest_tolerance_atr = 0.3;
   smcCfg.max_retest_bars = 10; smcCfg.sweep_lookback = 30; smcCfg.shift_lookback = 6;
   smcCfg.fvg_scan_bars = 15; smcCfg.trend_lookback = 5;
   SSMCSignal smcSig;
   SMC_EvaluateArray(opens, highs, lows, closes, atr_values, effective_regime, smcCfg, smcSig);
   candidates[1] = SS_FromSMC(smcSig);

   // 3. Chart Pattern
   SCPStrategyConfig cpCfg;
   cpCfg.depth = InpSwingDepth; cpCfg.max_lookback = InpMaxLookback;
   cpCfg.price_tolerance_atr = 1.0; cpCfg.min_pullback_atr = 1.5;
   cpCfg.min_head_prominence_atr = 1.0; cpCfg.time_tolerance = 0.5;
   cpCfg.trend_bars = 10; cpCfg.breakout_buffer_atr = 0.1; cpCfg.max_breakout_age_bars = 15;
   cpCfg.retest_tolerance_atr = 0.3; cpCfg.candlestick_trend_lookback = 5;
   SChartPatternStrategySignal cpSig;
   CPS_EvaluateArray(opens, highs, lows, closes, atr_values, effective_regime, structure, cpCfg,
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
   TFS_EvaluateArray(opens, highs, lows, closes, atr_values, effective_regime, tfCfg, tfSig);
   candidates[3] = SS_FromTrendFollowing(tfSig);

   // 5. Post-Expansion Retest
   SPERConfig perCfg;
   perCfg.depth = InpSwingDepth; perCfg.max_lookback = InpMaxLookback;
   perCfg.min_expansion_atr = 1.5; perCfg.retest_tolerance_atr = 0.3;
   perCfg.no_chase_bars = 2; perCfg.stop_buffer_atr = 0.1; perCfg.candlestick_trend_lookback = 5;
   SPostExpansionRetestSignal perSig;
   PER_EvaluateArray(opens, highs, lows, closes, atr_values, effective_regime, structure, perCfg,
                      perSig);
   candidates[4] = SS_FromPostExpansionRetest(perSig);

   SRoutedCandidate routed[];
   int eligible_count = STR_RouteCandidates(candidates, 5, effective_regime,
                                             regime_read.confidence, routed);

   SConflictResult resolution;
   bool has_decision = CR_ResolveConflicts(routed, 5, 10.0, resolution);

   //--- TASK-040 (rewritten, seventh-round P0 finding 6): journal            --
   //--- market_family and the CANONICAL TASK-002 section 1 intraday_mode ------
   //--- formula (four normalized components, weighted average, 0.40/0.60 -----
   //--- thresholds, neutral-band persistence, hysteresis) -- see                --
   //--- IntradayModeRouter.mqh's own header for the stated M1-vs-M15-              --
   //--- evaluation-cadence deviation. -----------------------------------------------
   double session_remaining_ratio, session_remaining_minutes;
   bool session_ratio_known = SN_GetSessionMinutesRemaining(g_symbol, session_remaining_ratio,
                                                              session_remaining_minutes);
   if(!session_ratio_known)
     {
      session_remaining_ratio = 0.0; // no session today (weekend/holiday) — treat as "none left"
                                      // for the MODE classifier only; session_state (below) keeps
                                      // this distinguished from a genuine low-ratio bar.
      session_remaining_minutes = 0.0;
     }

   IMR_UpdateTrendAge(g_mode_state, effective_regime);
   double range_atr_multiple = ComputeTodaySessionRangeAtrMultiple(highs, lows, atr_values[0]);

   SModeComponent mc_regime_persistence, mc_atr_percentile, mc_range, mc_session;
   mc_regime_persistence.available = true;
   mc_regime_persistence.value = IMR_ComputeRegimePersistence(effective_regime,
                                                                g_mode_state.trend_age_bars,
                                                                InpModePersistenceBars);
   mc_atr_percentile.available = true;
   mc_atr_percentile.value = MathMax(0.0, MathMin(1.0, regime_read.E));
   mc_range.available = (atr_values[0] > 0.0);
   mc_range.value = IMR_ComputeRangeVsAverage(range_atr_multiple);
   mc_session.available = session_ratio_known;
   mc_session.value = IMR_ComputeSessionTimeRemaining(session_remaining_ratio,
                                                        session_remaining_minutes,
                                                        InpMinDayTradeSessionMinutes);

   SModeWeights mode_weights = IMR_DefaultModeWeights();
   SModeScoreResult mode_score = IMR_ComputeModeScore(mc_regime_persistence, mc_atr_percentile,
                                                        mc_range, mc_session, mode_weights);
   ENUM_INTRADAY_MODE intraday_mode = IMR_ApplyModeHysteresis(g_mode_state, effective_regime,
                                                                mode_score,
                                                                InpModeHysteresisEvaluations);

   AppendReason(gate_reasons, "market_family_" + IMR_MarketFamilyToString(g_market_family));
   AppendReason(gate_reasons, StringFormat(
      "intraday_mode_%s_score_%s_components_%d", IMR_IntradayModeToString(intraday_mode),
      mode_score.valid ? DoubleToString(mode_score.mode_score, 4) : "undefined",
      mode_score.components_available));

   // TASK-036: news_state/session_state's exact canonical vocabulary,
   // matching analysis/performance_breakdown.py's own defined values --
   // "CLEAR"/"BLACKOUT" for news_state; the 3 SESSION_TIME_REMAINING_*
   // buckets for session_state (never labelling unreadable session data as
   // a fabricated LOW, per SN_GetSessionMinutesRemaining's own "exclude
   // it, never default it" rule).
   string news_state = news_blackout ? "BLACKOUT" : "CLEAR";
   string session_state;
   if(!session_ratio_known)
      session_state = "SESSION_TIME_REMAINING_UNKNOWN";
   else if(session_remaining_ratio >= 0.5)
      session_state = "SESSION_TIME_REMAINING_HIGH";
   else
      session_state = "SESSION_TIME_REMAINING_LOW";

   g_signal_counter++;
   string signal_id = StringFormat("%s_%I64d_%I64d", g_symbol, (long)TimeCurrent(),
                                    g_signal_counter);

   STradeDecision decision = DJ_NewDecision();
   decision.signal_id = signal_id;
   decision.timestamp = DJ_ServerTimeToUtc(TimeCurrent());
   decision.symbol = g_symbol;
   decision.market_family = IMR_MarketFamilyToString(g_market_family);
   decision.intraday_mode = IMR_IntradayModeToString(intraday_mode);
   decision.regime = EnumToString(effective_regime);
   decision.regime_confidence = regime_read.confidence * 100.0;
   decision.news_state = news_state;
   decision.session_state = session_state;
   decision.ea_version = "1.01-task027-order-submission-optional";

   // **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 6): TASK-002 section 1's stage-4 post-hoc mode-consistency check --
   // this is what makes intraday_mode actually ROUTE a trading decision,
   // not stay purely journal-only. A candidate whose own expected R is
   // incompatible with the confirmed mode (or whose mode is NONE --
   // gating override or undefined mode_score) is rejected outright, the
   // bar resolving to no-trade exactly like "no eligible candidate."**
   bool mode_consistent = false;
   if(has_decision)
     {
      double reward = MathAbs(resolution.winner.target_price - resolution.winner.entry_price);
      double risk = MathAbs(resolution.winner.entry_price - resolution.winner.stop_price);
      double expected_r = (risk > 0.0) ? (reward / risk) : 0.0;
      mode_consistent = IMR_IsCandidateConsistentWithMode(intraday_mode, expected_r,
                                                            InpMinDayTradeR, InpMaxScalpR);
      if(!mode_consistent)
         AppendReason(gate_reasons, StringFormat(
            "mode_consistency_rejected_mode_%s_expected_r_%.4f",
            IMR_IntradayModeToString(intraday_mode), expected_r));
     }

   if(has_decision && mode_consistent)
     {
      decision.direction = (resolution.winning_direction == CAND_LONG) ? "BUY" : "SELL";
      decision.strategy = EnumToString(resolution.winner.family);
      decision.setup = resolution.winner.setup;
      decision.candlestick_pattern = resolution.winner.candlestick_pattern;
      decision.entry = resolution.winner.entry_price;
      decision.has_entry = true;
      decision.stop = resolution.winner.stop_price;
      decision.has_stop = true;
      // TASK-036 Specification item 6: real per-component score breakdown,
      // matching exactly what SS_ComputeBaseScore/StrategyRouter.mqh
      // actually compute today (only these two components exist; the
      // three others SignalScorer.mqh's own header names are not
      // implemented and are NOT fabricated here).
      decision.score_breakdown_json = StringFormat(
         "{\"r_component\":%.6f,\"regime_component\":%.6f,\"eligibility_multiplier\":%.6f}",
         resolution.winner_r_component, resolution.winner_regime_component,
         resolution.winner_eligibility_multiplier);
      decision.targets_json = StringFormat("[%.5f]", resolution.winner.target_price);
      decision.score = resolution.winner_score;
      PrintFormat("ThembaEA: decision = %s %s via %s (%s), score=%.2f", decision.direction,
                  g_symbol, decision.strategy, decision.setup, decision.score);

      if(InpEnableOrderSubmission)
         AttemptOrderSubmission(decision, resolution, atr_values[0], gate_reasons,
                                 past_intraday_boundary);
      else
        {
         string skip_reasons[];
         for(int gi = 0; gi < ArraySize(gate_reasons); gi++)
            AppendReason(skip_reasons, gate_reasons[gi]);
         AppendReason(skip_reasons, "order_submission_disabled_InpEnableOrderSubmission_false");
         decision.reasons_rejected_json = BuildJsonStringArray(skip_reasons);
         Print("ThembaEA: JOURNAL ONLY — no order submitted (InpEnableOrderSubmission=false).");
        }
     }
   else
     {
      decision.direction = "NONE";
      decision.strategy = "NoTrade";
      decision.setup = has_decision ? "mode_consistency_rejected" : resolution.reason;
      decision.reasons_passed_json = BuildJsonStringArray(gate_reasons);
     }

   string journal_error;
   if(!DJ_AppendDecision(decision, journal_error))
      PrintFormat("ThembaEA: failed to journal this bar's decision: %s", journal_error);
  }
