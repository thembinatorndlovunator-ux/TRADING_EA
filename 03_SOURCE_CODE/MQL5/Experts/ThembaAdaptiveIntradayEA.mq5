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
#property version   "1.03"
#property description "Themba Adaptive Intraday Engine — decision pipeline; order submission is OFF by default (TASK-027, InpEnableOrderSubmission)."

// **Added, 2026-07-22 (Codex review finding, seventh round, P1 finding 18):
// decision.ea_version was a hard-coded, stale "task-027" string never
// updated across TASK-034/036/037/039/040/041, and decision.git_commit was
// never populated at all. MQL5 has NO runtime access to git metadata (no
// shell/process execution, and importing a WinAPI DLL to shell out to git
// would be a real stability/security concern for a live-trading EA this
// project has never accepted elsewhere) -- so THEMBA_EA_GIT_COMMIT is a
// STATED, MANUALLY-MAINTAINED build tag, not a live-queried value: update it
// by hand to the actual commit this file is compiled from immediately before
// each real release build. THEMBA_EA_VERSION_STRING mirrors #property
// version above (single source of truth referenced from both journal-writing
// call sites below, instead of the previous two independently-hardcoded
// literals that had already drifted out of sync with each other).**
// **Updated, 2026-07-27 (Codex round-8 P1 finding 21): the retained
// round-7 compile evidence attributed its build to commit 970cb39, seven
// commits behind the actual tip at compile time -- every journal record
// written by that binary claimed the wrong source commit. This value is
// updated immediately before generating this round's own compile evidence
// (09_HANDOVERS/compile_evidence/), matching this project's own stated
// convention above: it names the commit this exact tree state (this
// macro-update commit's own parent, containing every round-8 fix) was
// compiled from, not the macro-update commit itself, which changes only
// this string literal and no behavior.**
// **Updated again, 2026-07-28 (round-9 remediation, all 23 findings
// resolved): value now references 2e71e38, the last real content commit
// before this evidence pass -- round-9's own review (finding 21) found
// the PROSE DESCRIPTION of this same convention was wrong in round-8's
// evidence file (claimed the parent's tree was compiled when the child's
// actually was); the convention itself is unchanged and correct, only
// this round's own compile-evidence file's prose is written correctly
// from the start this time (see that file's own header).**
#define THEMBA_EA_VERSION_STRING "1.03-task028-round9"
#define THEMBA_EA_GIT_COMMIT     "2e71e38"

#include "../Include/ThembaEA/Routing/ConflictResolver.mqh"
#include "../Include/ThembaEA/Risk/BrokerValidator.mqh"
#include "../Include/ThembaEA/Risk/DailyWeeklyLimits.mqh"
#include "../Include/ThembaEA/Risk/EquityPeakManager.mqh"
#include "../Include/ThembaEA/Risk/DrawdownController.mqh"
#include "../Include/ThembaEA/Risk/CooldownManager.mqh"
#include "../Include/ThembaEA/Risk/NoStopGraceManager.mqh"
#include "../Include/ThembaEA/Risk/DailyWeeklyBreachManager.mqh"
#include "../Include/ThembaEA/Risk/RiskReservationManager.mqh"
#include "../Include/ThembaEA/Journal/DecisionJournal.mqh"
#include "../Include/ThembaEA/Journal/ExecutionEventJournal.mqh"
#include "../Include/ThembaEA/Execution/IntradayCloseManager.mqh"
#include "../Include/ThembaEA/Execution/OrderManager.mqh"
#include "../Include/ThembaEA/Execution/IntentManager.mqh"
#include "../Include/ThembaEA/Execution/ExitOrchestrator.mqh"
#include "../Include/ThembaEA/Execution/AsyncFillCorrelator.mqh"
#include "../Include/ThembaEA/Execution/CloseFinalizationTracker.mqh"
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
// **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding 9):
// TASK-002_PHASE2_SPECIFICATION.md section 6's own "Maximum age from
// confirmation: InpPatternMaxAgeBars (default 50)" -- previously not a
// real operator input at all (ChartPatternLifecycle.mqh's own
// CPL_GetConfirmedTime existed but had no production caller). See
// ChartPatternStrategy.mqh's own CPS_ApplyLifecycle for where this is now
// enforced.
input int    InpPatternMaxAgeBars = 50;

input ENUM_NEWS_PROVIDER_SOURCE InpNewsProviderSource = NEWS_PROVIDER_MT5_CALENDAR; // see note above
input string InpNewsCurrency               = "USD"; // "" = all currencies
input int    InpNewsMinImportance          = 3;      // high-impact only, section 10 default
input int    InpNewsBlackoutBeforeMinutes  = 15;
input int    InpNewsBlackoutAfterMinutes   = 15;
input int    InpNewsMaxExtensionMinutes    = 60;
// **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 2):
// TASK-002_PHASE2_SPECIFICATION.md's own UNTRADEABLE_SPREAD_OR_LIQUIDITY
// predicate default is 0.15, bounded [0.02, 1.0] -- this shipped at 3.0
// (twenty times the approved default, and beyond the allowed upper bound
// on its own), permitting a spread/ATR ratio far wider than the spec
// allows before the gate ever triggers. Corrected the default; OnInit now
// also rejects an out-of-range value at startup instead of silently
// running with one (see below).**
input double InpMaxSpreadAtrMultiple       = 0.15;   // shared: untradeable-spread gate AND
                                                       // news post-event spread-normalization check
                                                       // (bounded [0.02, 1.0], enforced at OnInit)
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
input bool   InpTimeStopUsesScalpMode      = true; // TASK-041, **fallback only as of the eighth-
                                                     // round P1 finding 13 fix**: which time-stop
                                                     // duration ceiling (InpScalpMaxMinutes vs
                                                     // remaining-session-time) applies. Each
                                                     // position now persists its OWN confirmed
                                                     // intraday_mode at entry time
                                                     // (PositionStateTracker.mqh's own
                                                     // entry_was_scalp_mode field, captured in
                                                     // AttemptOrderSubmission) and ManageOpenPositions
                                                     // reads THAT per-position value -- this global
                                                     // input is only consulted for a position that
                                                     // predates this fix (opened before entry_mode_
                                                     // captured existed) or was opened by a mechanism
                                                     // outside AttemptOrderSubmission.

input bool   InpEnableOrderSubmission     = false; // MASTER SAFETY TOGGLE — see file header
// **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 3):
// 0.30% sat OUTSIDE section 8's own stated 0.25-0.50% metals/synthetics
// range and above XAUUSD's own tighter 0.25% hard limit -- 0.25% is the one
// value valid across EVERY listed asset category (XAUUSD 0.25%, other
// metals/synthetics 0.25-0.50%), so it is the only safe blanket default.**
input double InpRiskPercentTarget         = 0.25;  // per-trade target risk %, within section 8's
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
// **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 3):
// section 8's no-SL fallback worst-case formula and its mandatory-remediation
// grace period -- see ComputeOwnMagicOpenRiskCash and EnforceNoStopGracePeriod.**
input double InpNoStopWorstCaseATRMultiple = 10.0;  // section 8 no-SL fallback default
input int    InpNoStopGraceSeconds        = 5;      // section 8: close immediately if unremediated
// **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 5):
// section 11's durable-intent abandonment timeout -- see
// ReconcileIntentAndFeedAFC/IntentManager.mqh's own IM_ReconcileOnRestart.**
input int    InpIntentTimeoutSeconds      = 30;     // section 11 default
// **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 10):
// section 8's InpIntradayBoundaryServerTime was previously only a hard-coded
// default in SN_IsPastIntradayBoundary/ICM_ShouldExecuteIntradayClose's own
// function arguments, never a real operator input -- see OnInit's own bounds
// check below and ICM_ReconcileIntradayClose's call sites (OnInit/OnTick/
// OnTimer) for where these are actually threaded through now.**
input int    InpIntradayBoundaryHour      = 23;     // section 8 default (server time)
input int    InpIntradayBoundaryMinute    = 45;     // section 8 default (server time)

CMarketData             g_md;
CSymbolProfile          g_profile;
string                  g_symbol;
datetime                g_last_evaluated_bar_time = 0;
SRegimeHysteresisState  g_hysteresis_state;
SModeState              g_mode_state; // TASK-040 (seventh-round rewrite): canonical mode formula's own state
ENUM_MARKET_FAMILY      g_market_family = MARKET_FAMILY_UNKNOWN;
long                    g_signal_counter = 0; // TASK-036: in-process counter feeding signal_id
// **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 4):
// true only when this bar's daily/weekly baseline and cash-flow-adjustment
// persistence all genuinely succeeded -- AttemptOrderSubmission's gate 2
// fails closed (rejects new entries) whenever this is false, rather than
// letting an absent/stale baseline read as "no breach". See
// EvaluateAndJournal's own comment for the full failure mode this closes.
bool                    g_daily_weekly_risk_state_valid = false;

// **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 2):**
// set every tick in OnTick from EPM_UpdateDailyPeak()/EPM_UpdateAccountPeak()'s
// own return values -- see EvaluateAndJournal's own gate 3 for why an unknown
// peak state (a lock-timeout write failure, or a peak that has genuinely
// never been recorded yet) must fail closed rather than silently reading as
// "zero drawdown, full risk size", same fail-closed pattern as
// g_daily_weekly_risk_state_valid above.
bool                    g_peak_state_valid = false;

// **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 6):**
// tracks whether EventSetTimer(30) (armed at OnInit) is currently active --
// see OnInit's own comment for why its return value must not be discarded.
// OnTick retries arming it every tick while this is false.
bool                    g_timer_armed = false;

int OnInit()
  {
   // **Superseded, 2026-07-27 (Codex review finding, ninth round, P0 finding
   // 2): SM_EnsureAccountLockInitialized is now a no-op. The account lock's
   // bootstrap is folded directly into SM_AcquireAccountLock itself (race-
   // free via GetLastError()'s ERR_GLOBALVARIABLE_NOT_FOUND signal), so
   // every StateManager call below (including SM_EnsureAccountSchema) is
   // already safe to call first, from any context -- this call is kept
   // only so this line does not need to be deleted.**
   SM_EnsureAccountLockInitialized();

   // **Added, 2026-07-22 (Codex review finding, seventh round, P1 finding
   // 14): this EA never called SM_EnsureAccountSchema() anywhere -- the
   // schema-migration routine StateManager.mqh already provides (and
   // documents as the mechanism a later schema bump's additive migration
   // depends on) was simply dead code as far as this EA's own runtime was
   // concerned.**
   SM_EnsureAccountSchema();

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

   // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 7):
   // the check above only validated the TARGET stays within the operator's
   // own configured CAP -- nothing validated the cap itself (or the daily/
   // weekly caps) against RISK_POLICY.md's own stated MAXIMA (1.00% hard
   // per-trade/total-open-risk cap, 2.00% daily, 4.00% weekly). An operator
   // could configure every field labelled "hard" in this project's own
   // documentation to a value ABOVE the policy that names them hard limits
   // in the first place, and nothing would refuse to run.**
   if(InpRiskCapPercent > 1.0 + 1e-9)
     {
      PrintFormat("ThembaEA: invalid InpRiskCapPercent=%.4f -- exceeds RISK_POLICY.md's own "
                  "stated hard per-trade/total-open-risk cap maximum of 1.00%%. Refusing to run.",
                  InpRiskCapPercent);
      return INIT_FAILED;
     }
   if(InpDailyLossCapPercent <= 0.0 || InpDailyLossCapPercent > 2.0 + 1e-9)
     {
      PrintFormat("ThembaEA: invalid InpDailyLossCapPercent=%.4f -- must be positive and not "
                  "exceed RISK_POLICY.md's own stated daily loss cap maximum of 2.00%%. "
                  "Refusing to run.", InpDailyLossCapPercent);
      return INIT_FAILED;
     }
   if(InpWeeklyLossCapPercent <= 0.0 || InpWeeklyLossCapPercent > 4.0 + 1e-9)
     {
      PrintFormat("ThembaEA: invalid InpWeeklyLossCapPercent=%.4f -- must be positive and not "
                  "exceed RISK_POLICY.md's own stated weekly loss cap maximum of 4.00%%. "
                  "Refusing to run.", InpWeeklyLossCapPercent);
      return INIT_FAILED;
     }

   // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 7):
   // InpMagicNumber was never required to be nonzero. Zero is MT5's own
   // "unset"/wildcard-like value in several contexts, and -- more
   // concretely for this project's own risk logic -- every own-magic
   // ownership scan throughout this EA (ComputeOwnMagicOpenRiskCash,
   // EnforceNoStopGracePeriod, ICM_CloseAllOwnedPositions, etc.) filters by
   // `POSITION_MAGIC == InpMagicNumber`/`ORDER_MAGIC == InpMagicNumber`. If
   // an operator ever configured InpMagicNumber=0 (whether by mistake or
   // because 0 looks like a harmless default), any MANUAL position/order
   // placed with no magic number at all (MT5's own actual default) would
   // match every one of these scans -- exposing a human's own manual
   // trading to this EA's bulk mandatory-close/breach-closure logic.**
   if(InpMagicNumber == 0)
     {
      Print("ThembaEA: invalid InpMagicNumber=0 -- a zero magic number would make manual "
            "positions/orders (MT5's own default magic) match every one of this EA's own-magic "
            "ownership scans, exposing them to bulk mandatory closure. Refusing to run.");
      return INIT_FAILED;
     }

   // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 7):
   // the stop floor must stay strictly below the stop cap -- with the floor
   // ABOVE the cap, RM_ValidateStopDistance's own "widen a tighter stop out
   // to the floor" branch can widen an already-cap-validated stop distance
   // to a value that itself exceeds the cap, silently defeating the very
   // cap check that ran immediately before it.**
   if(InpStopFloorAtrMultiple >= InpStopCapAtrMultiple)
     {
      PrintFormat("ThembaEA: invalid stop floor/cap configuration -- InpStopFloorAtrMultiple=%.4f "
                  "must be strictly less than InpStopCapAtrMultiple=%.4f (a floor at or above the "
                  "cap can widen an already-validated stop past the cap). Refusing to run.",
                  InpStopFloorAtrMultiple, InpStopCapAtrMultiple);
      return INIT_FAILED;
     }

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 2):
   // TASK-002_PHASE2_SPECIFICATION.md bounds InpMaxSpreadATRMultiple to
   // [0.02, 1.0] -- an out-of-range operator value (or the previous default
   // of 3.0, itself out of range) must be refused at startup, not silently
   // widen the untradeable-spread gate and the news post-event spread-
   // normalization check it shares.**
   if(InpMaxSpreadAtrMultiple < 0.02 || InpMaxSpreadAtrMultiple > 1.0)
     {
      PrintFormat("ThembaEA: invalid InpMaxSpreadAtrMultiple=%.4f -- must be in [0.02, 1.0] per "
                  "TASK-002_PHASE2_SPECIFICATION.md. Refusing to run.", InpMaxSpreadAtrMultiple);
      return INIT_FAILED;
     }

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 10):
   // InpIntradayBoundaryHour/Minute is now a real, validated operator input
   // (previously only a hard-coded function-argument default) -- an
   // out-of-range value would otherwise silently corrupt every downstream
   // SN_IsPastIntradayBoundary/ICM_ReconcileIntradayClose call.**
   if(InpIntradayBoundaryHour < 0 || InpIntradayBoundaryHour > 23 ||
      InpIntradayBoundaryMinute < 0 || InpIntradayBoundaryMinute > 59)
     {
      PrintFormat("ThembaEA: invalid intraday boundary %02d:%02d -- hour must be [0,23] and "
                  "minute [0,59]. Refusing to run.", InpIntradayBoundaryHour,
                  InpIntradayBoundaryMinute);
      return INIT_FAILED;
     }

   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 1):
   // this guard was EXACTLY INVERTED -- TASK-002_PHASE2_SPECIFICATION.md
   // section "Netting vs. hedging account-mode support" states plainly:
   // "hedging-mode only, full stop, no promised future phase. The engine
   // validates and requires a hedging-mode account at OnInit and refuses to
   // run otherwise; netting-account support, if ever wanted, is a separate,
   // fully-specified task." The seventh-round fix required netting and
   // refused hedging -- the opposite of the canonical decision. Flipped.
   // The one place this project's own logic previously assumed "at most one
   // position per symbol+magic can ever exist" in a way that would have been
   // unsafe under hedging (OM_OpenPosition's post-open lookup, which scanned
   // symbol+magic and took the FIRST match) is also fixed this round to use
   // the causally-correct DEAL_POSITION_ID from the fill's own deal instead
   // -- see that function's own comment. Every OTHER position-scanning site
   // in this codebase (ManageOpenPositions, ComputeOwnMagicOpenRiskCash,
   // ICM_CloseAllOwnedPositions, the no-add-on gate) already iterates EVERY
   // matching position or uses a specific ticket/position_id, never a "take
   // the first" heuristic, so hedging mode does not silently break them.**
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) !=
      ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("ThembaEA: this account is NOT in HEDGING margin mode -- "
            "TASK-002_PHASE2_SPECIFICATION.md requires a hedging-mode account, full stop. "
            "Refusing to run.");
      return INIT_FAILED;
     }

   g_symbol = (InpTradeSymbol == "") ? _Symbol : InpTradeSymbol;

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 3):
   // restart reconciliation for a daily/weekly breach closure that was still
   // in flight when this instance last stopped -- per section 8, "on
   // restart, a pending closure_pending record is the first thing
   // reconciled." A single attempt here is enough to bring most restarts
   // fully current; OnTick's own retry-until-closed loop (see OnTick) covers
   // anything this attempt does not immediately finish. This early, cheap
   // check runs before profile load/other init steps that could still fail
   // and return INIT_FAILED -- ReEvaluateMandatoryClosureObligations()
   // later in this function (Codex round-10 P0 findings 6/7) is the
   // comprehensive ground-truth pass that also covers a closure obligation
   // whose OWN persisted flag never survived a prior crash; redundant with
   // this block when both find the same pending flag, which is harmless
   // (DWB_AttemptClosure is idempotent).**
   if(DWB_IsClosurePending(g_symbol, InpMagicNumber))
     {
      string reconcile_reasons[];
      bool reconciled = DWB_AttemptClosure(g_symbol, InpMagicNumber, reconcile_reasons);
      PrintFormat("ThembaEA: restart reconciliation found a pending daily/weekly breach "
                  "closure -- %s.", reconciled ? "fully closed" : "still retrying every tick");
     }

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
   //
   // **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding
   // 7): this guard previously only fired when the SYMBOL_PATH-based
   // classifier POSITIVELY returned METAL or FOREX -- a real metal/forex
   // symbol under a broker path this classifier's own keyword list does not
   // recognize comes back MARKET_FAMILY_UNKNOWN instead, silently slipping
   // past this check and reaching NEWS_PROVIDER_NONE's unconditional "no
   // blackout" behavior on a symbol that may genuinely need the mandatory
   // filter. MARKET_FAMILY_SYNTHETIC_INDEX is the ONLY family this
   // classifier positively confirms NONE is safe for (per its own
   // recognized synthetic-index keyword list); UNKNOWN must be treated with
   // the same suspicion as a confirmed metal/forex symbol -- fail closed
   // (refuse to run) rather than assume the classifier's own blind spot
   // means "safe to skip the mandatory filter."**
   if(InpNewsProviderSource == NEWS_PROVIDER_NONE &&
      g_market_family != MARKET_FAMILY_SYNTHETIC_INDEX)
     {
      PrintFormat("ThembaEA: InpNewsProviderSource=NEWS_PROVIDER_NONE is not permitted on a "
                  "%s symbol ('%s') -- the macro news-blackout filter is mandatory for every "
                  "market family this classifier does not POSITIVELY confirm is a synthetic "
                  "index (an UNKNOWN classification may still be a real metal/forex symbol under "
                  "an unrecognized broker path). Select MT5_CALENDAR or FAIR_ECONOMY. "
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
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 5): now
   // delegates to ReconcileIntentAndFeedAFC(), which also searches closed
   // history and reconstructs AsyncFillCorrelator's pending record — see
   // that function's own header and OnTick's own repeated call to it.**
   ReconcileIntentAndFeedAFC();

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 10):
   // reconciles a still-owed intraday close from an EARLIER day (crash
   // before it completed, or a tick-starved gap across midnight) before
   // this instance resumes normal operation -- "reconcile the previous
   // day's unfinished close before allowing any new entry." A single
   // attempt here is enough to bring most restarts fully current; OnTick's
   // and OnTimer's own repeated calls (see below) cover anything this one
   // does not immediately finish.**
   bool close_reconciled = ICM_ReconcileIntradayClose(g_symbol, InpMagicNumber,
                                                        InpIntradayBoundaryHour,
                                                        InpIntradayBoundaryMinute);
   if(!close_reconciled)
      PrintFormat("ThembaEA: restart reconciliation found a still-owed intraday close for '%s' "
                  "magic %I64d -- not yet fully closed, will keep retrying every tick/timer.",
                  g_symbol, InpMagicNumber);

   // **Added, 2026-07-28 (Codex review finding, tenth round, P0 finding 7):**
   // establish the daily/weekly risk-state validity flag NOW, at restart,
   // before any deal/tick can be processed -- previously this stayed false
   // (its OnInit-time default) until the first completed-bar evaluation, a
   // window in which a deal arriving early (e.g. while reconciling
   // pre-existing own-magic exposure just above) could skip the account-wide
   // daily/weekly check entirely. See EstablishDailyWeeklyRiskState's own
   // header.
   EstablishDailyWeeklyRiskState();

   // **Added, 2026-07-28 (Codex review findings, tenth round, P0 findings 6
   // and 7):** ground-truth re-evaluation of every mandatory closure
   // condition, run once here at restart -- closes finding 6's own
   // "DailyWeeklyBreachManager's fallback does not survive restart" gap (a
   // closure obligation lost to a crash before its persisted flag ever wrote
   // is REDISCOVERED here from current baseline/position state, not
   // dependent on that flag having survived) and finding 7's own "unknown
   // daily/weekly state must... create a durable, repeatedly evaluated fail-
   // closed obligation for existing exposure" requirement (an unreadable
   // state right here at restart now arms closure immediately, not just a
   // future new-entry block). See ReEvaluateMandatoryClosureObligations's
   // own header; also called every tick and every timer fire below.
   ReEvaluateMandatoryClosureObligations();

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 10):
   // a timer guarantees the mandatory intraday close is attempted even if
   // NO TICK arrives at or after the boundary before the next server
   // midnight -- previously the close only ran from OnTick, so a
   // tick-starved period (illiquid symbol, off-hours) could let the
   // boundary pass with no close attempt at all, and the very next day's
   // first tick would silently reset SN_IsPastIntradayBoundary() to false
   // for the new day, discarding the unfulfilled obligation. 30 seconds is
   // frequent enough to close well within the boundary window without
   // meaningful overhead.
   //
   // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 6):
   // this return value was previously discarded -- EventSetTimer can fail
   // (e.g. transient resource exhaustion), which would silently remove the
   // whole no-tick guarantee this fix exists for, with no record of it
   // having happened. g_timer_armed now tracks the outcome; a failure is
   // logged loudly and OnTick retries EventSetTimer on every tick until it
   // succeeds (a cheap, idempotent registration call), so the guarantee is
   // restored as soon as possible instead of never.**
   //
   // **Fixed, 2026-07-28 (Codex review finding, tenth round, P0 finding 6):
   // a timer failure previously still returned INIT_SUCCEEDED and could
   // enable real order submission -- every wall-clock mandatory protection
   // this timer exists to guarantee (intraday close, no-stop grace-period
   // closure, mandatory daily/weekly/total-risk closure re-evaluation) would
   // then depend entirely on ticks arriving, with no independent guarantee
   // during a tick-starved period. Now refuses to initialize with order
   // submission enabled unless the timer is genuinely active -- journal-only
   // mode (no real exposure ever created) may still proceed without it, but
   // is explicitly still logged as running with a reduced guarantee.**
   g_timer_armed = EventSetTimer(30);
   if(!g_timer_armed)
     {
      if(InpEnableOrderSubmission)
        {
         PrintFormat("ThembaEA: REFUSING TO INITIALIZE -- EventSetTimer(30) failed (error=%d) and "
                     "InpEnableOrderSubmission=true. Every wall-clock mandatory protection "
                     "(intraday close, no-stop grace-period closure, daily/weekly/total-risk "
                     "closure re-evaluation) requires a working independent timer to guarantee "
                     "coverage during a tick-starved period; running order-enabled without one is "
                     "not permitted.", GetLastError());
         return INIT_FAILED;
        }
      PrintFormat("ThembaEA: CRITICAL -- EventSetTimer(30) FAILED at OnInit (error=%d). The "
                  "no-tick mandatory-close guarantee is NOT currently active; OnTick will retry "
                  "arming the timer every tick until it succeeds. Proceeding because "
                  "InpEnableOrderSubmission=false (journal-only mode -- no real exposure is ever "
                  "created).", GetLastError());
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
//| **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding 9):  |
//| finds the DEAL_ENTRY_IN deal ticket tied to 'order_ticket', for a          |
//| TRADE_TRANSACTION_HISTORY_ADD resolution where the specific fill deal        |
//| is not otherwise in scope (unlike the DEAL_ADD handler, which already          |
//| has trans.deal directly). Bounded to a trailing 2-day HistorySelect            |
//| window, matching GetPositionEntryCosts' own convention elsewhere in               |
//| this file (this project's own positions are always closed same-day).                |
//| Returns 0 (left null in the journal, never fabricated) if no matching                   |
//| deal is found within that window.                                                          |
//+------------------------------------------------------------------+
ulong FindFillDealForOrder(const ulong order_ticket)
  {
   datetime from = TimeTradeServer() - 2 * 86400;
   datetime to   = TimeTradeServer() + 60;
   if(!HistorySelect(from, to))
      return 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;
      if((ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER) != order_ticket)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         return deal_ticket;
     }
   return 0;
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
//| expectations. Rather than patch each individual defect, this logged the                 |
//| resolution for operator visibility ONLY (Print, no journal row) and                        |
//| named a real, schema-correct async event record as a genuine follow-up.**                     |
//|                                                                    |
//| **Extended, 2026-07-27 (Codex review finding, ninth round, P1 finding   |
//| 9): that follow-up. Every resolution now ALSO appends a schema-correct       |
//| SExecutionEvent row via ExecutionEventJournal.mqh -- a genuinely             |
//| separate, append-only journal keyed by signal_id/intent_id/order_id/           |
//| deal_id, distinct from STradeDecision, so an async fill/cancel outcome            |
//| is real machine-readable evidence, not just an Experts-log line. This               |
//| also closes the review's crash-window complaint: this event does not                  |
//| depend on the original PLACED decision's own DJ_AppendDecision call                       |
//| having succeeded (or having run at all) -- it is independently useful                        |
//| evidence that a fill/cancellation happened, keyed by whatever IDs are                            |
//| known at this call site.**                                                                           |
//+------------------------------------------------------------------+
void LogAsyncFillResolution(const string original_signal_id, const string intent_id,
                             const bool filled, const ulong resolved_position_id,
                             const ulong order_ticket, const ulong deal_ticket,
                             const string event_type, const string outcome_note)
  {
   if(filled)
      PrintFormat("ThembaEA: async fill resolved for signal_id=%s -- position_id=%I64u (%s).",
                  original_signal_id, resolved_position_id, outcome_note);
   else
      PrintFormat("ThembaEA: async order resolved WITHOUT filling for signal_id=%s (%s).",
                  original_signal_id, outcome_note);

   SExecutionEvent evt = EEJ_NewEvent();
   datetime event_time_utc = DJ_ServerTimeToUtc(TimeTradeServer());
   evt.event_id = EEJ_BuildEventId(event_time_utc, GetMicrosecondCount());
   evt.event_type = event_type;
   evt.signal_id = original_signal_id;
   evt.intent_id = intent_id;
   if(resolved_position_id != 0)
      evt.order_id = IntegerToString((long)resolved_position_id);
   evt.order_ticket = order_ticket;
   if(deal_ticket != 0)
      evt.deal_id = IntegerToString((long)deal_ticket);
   evt.timestamp = event_time_utc;
   evt.symbol = g_symbol;
   evt.filled = filled;
   evt.outcome_note = outcome_note;

   string event_error;
   if(!EEJ_AppendEvent(evt, event_error))
      PrintFormat("ThembaEA: CRITICAL -- failed to append execution-event journal row for "
                  "signal_id=%s event_type=%s (%s). The async resolution above still took full "
                  "effect (durable intent/reservation/correlator state are unaffected by this "
                  "journal write's own success) -- only this row's own machine-readable evidence "
                  "is missing.", original_signal_id, event_type, event_error);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, seventh round, P1 finding    |
//| 14):** true iff a position carrying POSITION_IDENTIFIER == 'position_id'    |
//| is still open on this account, on ANY symbol/magic — used to distinguish       |
//| "this closing deal fully closed the position" from "a broker-side              |
//| partial fill left a smaller remainder still open under the same                  |
//| position_id" before clearing that position's own tracked exit state.               |
//+------------------------------------------------------------------+
bool PositionStillOpenById(const ulong position_id)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == position_id)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding 8):  |
//| factored out of OnTradeTransaction's DEAL_ENTRY_OUT/OUT_BY/INOUT              |
//| handling so it can ALSO be called from ReconcilePendingCloseFinalizations()      |
//| below, once a position confirmed closed later than the ORIGINAL closing              |
//| deal's own callback (see that function's own header for the race this                    |
//| closes). Caller MUST have already confirmed !PositionStillOpenById(position_id)               |
//| -- this function does not re-check.                                                              |
//+------------------------------------------------------------------+
void FinalizeClosedPosition(const ulong closed_position_id)
  {
   double total_pnl = CDM_GetAccumulatedPositionPnl(closed_position_id) +
                       GetPositionEntryCosts(closed_position_id);
   if(!CDM_RecordClosedTrade(g_symbol, InpMagicNumber, total_pnl, TimeCurrent(),
                              InpCooldownMinutes))
      PrintFormat("ThembaEA: CooldownManager failed to persist a closed-trade "
                  "record for '%s' magic %I64d -- the 3-loss cooldown ledger may "
                  "be missing this trade.", g_symbol, InpMagicNumber);
   CDM_ClearAccumulatedPositionPnl(closed_position_id);

   PST_Clear(closed_position_id);
   NSG_Clear(closed_position_id);
   CIFT_ClearCloseInFlight(closed_position_id);
   PCF_ClearPendingFinalization(closed_position_id);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding 8):  |
//| re-checks every position_id CloseFinalizationTracker.mqh has marked as     |
//| awaiting finalization (its own closing deal was observed, but                  |
//| PositionStillOpenById() still read true at that exact processing moment            |
//| -- MT5 does not guarantee transaction-type arrival order) and completes                 |
//| finalization now that the position list has caught up. Call from OnTick                    |
//| and OnTimer -- durable/restart-survivable (the mark is a persisted                              |
//| GlobalVariable, not session-only), so this also recovers an obligation                              |
//| that outlived a crash between the original DEAL_ADD callback and this                                  |
//| reconciliation.                                                                                            |
//+------------------------------------------------------------------+
void ReconcilePendingCloseFinalizations()
  {
   ulong pending_ids[16];
   int count = PCF_FindPendingFinalizations(pending_ids);
   for(int i = 0; i < count; i++)
     {
      if(!PositionStillOpenById(pending_ids[i]))
         FinalizeClosedPosition(pending_ids[i]);
      // Still open -- leave the mark in place, retried on a later
      // tick/timer fire.
     }
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding    |
//| 13):** sums the entry-side commission/fee for 'position_id' -- the           |
//| cooldown P/L figure previously only summed CLOSING-deal costs               |
//| (DEAL_PROFIT/SWAP/COMMISSION/FEE), omitting whatever commission/fee               |
//| the OPENING deal(s) themselves charged. DEAL_PROFIT/DEAL_SWAP are                    |
//| deliberately excluded here (an opening deal has neither a realized              |
//| profit nor an accrued swap yet) -- only DEAL_COMMISSION/DEAL_FEE, the                 |
//| genuine entry-side transaction costs, are allocated. Bounded to a               |
//| trailing 2-day HistorySelect window (this project's own positions are             |
//| always closed same-day by the mandatory intraday boundary, so 2 days is                |
//| comfortably more than any real position's lifetime, matching                              |
//| DailyWeeklyLimits.mqh's own bounded-window convention elsewhere).                             |
//+------------------------------------------------------------------+
double GetPositionEntryCosts(const ulong position_id)
  {
   datetime from = TimeTradeServer() - 2 * 86400;
   datetime to   = TimeTradeServer() + 60;
   if(!HistorySelect(from, to))
      return 0.0;

   double costs = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID) != position_id)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      costs += HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_FEE);
     }
   return costs;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 5):** shared durable-intent reconciliation, called once from OnInit          |
//| (restart) and again every tick from OnTick while an intent remains              |
//| unresolved by the normal live-position/live-order paths -- a single OnInit          |
//| call is not always sufficient: an intent found with NO live position, NO             |
//| live order, and NO closed-history trace, but still younger than                          |
//| InpIntentTimeoutSeconds, is left active by IM_ReconcileOnRestart pending                     |
//| a later re-check (the broker may simply not have responded to the crash-                        |
//| interrupted submission yet), and this is the only place that re-check                              |
//| happens. Also reconstructs AsyncFillCorrelator.mqh's session-only pending                              |
//| array when a still-live pending order is found -- without this, a                                        |
//| still-pending order surviving a restart could never be resolved by the                                       |
//| normal OnTradeTransaction/AFC_FindPending path (that array is empty after                                        |
//| every restart), leaving the intent stuck until yet another restart.**                                                |
//+------------------------------------------------------------------+
void ReconcileIntentAndFeedAFC()
  {
   bool  orphaned_was_filled, orphaned_still_pending, orphaned_abandoned;
   ulong orphaned_pending_ticket;
   if(!IM_ReconcileOnRestart(g_symbol, InpMagicNumber, InpIntentTimeoutSeconds,
                              orphaned_was_filled, orphaned_still_pending,
                              orphaned_pending_ticket, orphaned_abandoned))
      return; // no active intent -- nothing to reconcile

   if(orphaned_still_pending && orphaned_pending_ticket != 0)
     {
      string existing_signal_id;
      int    existing_index;
      string existing_reservation_key;
      bool   existing_was_scalp_mode;
      if(!AFC_FindPending(orphaned_pending_ticket, existing_signal_id, existing_index,
                           existing_reservation_key, existing_was_scalp_mode))
        {
         string synthetic_signal_id = StringFormat("restart_reconciled_%s",
                                                     IM_GetIntentId(g_symbol, InpMagicNumber));
         AFC_AddPending(orphaned_pending_ticket, synthetic_signal_id);
         PrintFormat("ThembaEA: reconciliation found a still-pending order #%I64u for '%s' magic "
                     "%I64d -- reconstructed async-fill correlation (synthetic signal_id=%s) so "
                     "its eventual outcome resolves through the normal OnTradeTransaction path.",
                     orphaned_pending_ticket, g_symbol, InpMagicNumber, synthetic_signal_id);
        }
      return;
     }

   if(orphaned_still_pending)
      return; // too young to conclude anything yet -- retried on a later tick

   string reconcile_outcome;
   if(orphaned_abandoned)
      reconcile_outcome = StringFormat("no trace found anywhere and the intent is older than "
                                        "InpIntentTimeoutSeconds=%d -- treated as abandoned",
                                        InpIntentTimeoutSeconds);
   else if(orphaned_was_filled)
      reconcile_outcome = "a matching live position or closed-history fill record exists "
                           "(order had filled)";
   else
      reconcile_outcome = "resolved in closed history as cancelled/expired/rejected (order "
                           "never filled), or no matching position/order/history trace exists "
                           "at all (order never reached the broker)";
   PrintFormat("ThembaEA: reconciled an orphaned durable-intent record for '%s' magic %I64d -- "
               "%s.", g_symbol, InpMagicNumber, reconcile_outcome);

   // **Added, 2026-07-28 (Codex review finding, tenth round, P0 finding 2):**
   // a reservation whose own holder crashed before releasing it (the
   // process died between RRM_TryReserve and the eventual
   // RRM_ReleaseReservation call) would otherwise sit in the cap sum
   // forever -- RiskReservationManager.mqh's own sum no longer ages
   // anything out automatically (see that module's header for why a
   // blind time-based exclusion was itself the review's finding). This is
   // the caller-driven reconciliation point that replaces it: every
   // branch above (abandoned / filled / resolved-not-filled) is
   // DEFINITIVELY TERMINAL for this exact intent (the still-pending
   // branches above both return earlier without reaching here), so any
   // reservation still aged-present under THIS symbol+magic's own
   // namespace at this point can only be a leftover from a PRE-restart
   // attempt whose own disposition this reconciliation pass has now
   // independently proven -- safe to release, never before.
   string aged_keys[8];
   int aged_count = RRM_FindAgedReservations(InpMagicNumber, RRM_STALE_SECONDS, aged_keys);
   for(int ai = 0; ai < aged_count; ai++)
     {
      if(StringFind(aged_keys[ai], RRM_SymbolPrefix(g_symbol, InpMagicNumber)) != 0)
         continue; // a different symbol under this same magic -- not this reconciliation's to touch
      PrintFormat("ThembaEA: releasing a pre-restart risk reservation ('%s') now that its own "
                  "intent has been proven terminal by the reconciliation above.", aged_keys[ai]);
      RRM_ReleaseReservation(aged_keys[ai]);
     }
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
      // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding
      // 3): daily/weekly loss-cap breach detection, per section 8: "breach
      // detection happens inside the OnTradeTransaction handler at the
      // moment the filling deal is reported... the closure order is
      // submitted synchronously from that same handler." Deliberately
      // UNFILTERED by magic/symbol -- the caps are measured against total
      // ACCOUNT equity change ("a loss is a loss regardless of which EA
      // caused it"), so every deal on the account (this EA's own, a
      // different EA's, or manual) can be the one that tips the account
      // over the cap, and every one must be checked. ACCOUNT_EQUITY already
      // reflects this deal's own fill by the time this handler runs. Skips
      // if a closure is already pending -- OnTick's own retry loop is
      // already driving that one to completion; re-arming here would just
      // restate the same persisted flag redundantly.
      //
      // **Moved above the HistoryDealSelect gate below, 2026-07-27 (Codex
      // review finding, ninth round, P0 finding 1): this check reads only
      // ACCOUNT_EQUITY (via DWL_IsDailyLossBreached/DWL_IsWeeklyLossBreached),
      // never any trans.deal-specific field -- it does NOT need
      // HistoryDealSelect(trans.deal) to have succeeded at all. Running it
      // AFTER that select meant a HistoryDealSelect failure (rare, but a
      // real possible broker/terminal glitch, not provably impossible)
      // bypassed the mandatory daily/weekly breach check entirely for that
      // fill event -- exactly the "fail-open on an unreadable component"
      // defect this same finding closes elsewhere in this function.**
      // **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding
      // 8): a cash-flow (deposit/withdrawal/credit) deal is itself a
      // DEAL_ADD event reaching this same handler, but the daily/weekly
      // baseline was previously only rebased for it on the NEXT completed
      // bar's own EvaluateAndJournal cycle -- every deal in between
      // (including this exact cash-flow deal) evaluated the breach check
      // below against the STALE, pre-rebase baseline. A withdrawal can
      // transiently look like a large trading loss against that stale
      // baseline and force-close real exposure for no real reason
      // (reviewer's own example: a 300 withdrawal against a 10,000
      // baseline reads as -3% until rebased, after which it is 0%).
      // DWL_ApplyCashFlowAdjustments is idempotent (a persisted cursor
      // tracks the last-processed deal ticket) -- calling it again here,
      // on every deal, is always safe and picks up THIS exact cash-flow
      // deal (already in history by the time OnTradeTransaction fires)
      // before the breach check below ever runs. Only ever moves
      // g_daily_weekly_risk_state_valid to false on a failure here, never
      // back to true -- that flag's own true state depends on the daily/
      // weekly BASELINES too (EvaluateAndJournal's own per-bar check),
      // which this call does not re-verify.**
      if(!DWL_ApplyCashFlowAdjustments())
         g_daily_weekly_risk_state_valid = false;

      if(!DWB_IsClosurePending(g_symbol, InpMagicNumber))
        {
         double breach_daily_change, breach_weekly_change;
         bool daily_breached  = g_daily_weekly_risk_state_valid &&
                                 DWL_IsDailyLossBreached(InpDailyLossCapPercent, breach_daily_change);
         bool weekly_breached = g_daily_weekly_risk_state_valid &&
                                 DWL_IsWeeklyLossBreached(InpWeeklyLossCapPercent, breach_weekly_change);
         if(daily_breached || weekly_breached)
           {
            string breach_reasons[];
            bool breach_closed = DWB_AttemptClosure(g_symbol, InpMagicNumber, breach_reasons);
            PrintFormat("ThembaEA: daily/weekly loss cap breach detected on fill (deal #%I64u) -- "
                        "daily_breached=%s weekly_breached=%s, closure %s.",
                        trans.deal, daily_breached ? "true" : "false",
                        weekly_breached ? "true" : "false",
                        breach_closed ? "completed" : "pending (will retry every tick)");
           }
        }

      // Every remaining branch below (position mode/cooldown bookkeeping,
      // the post-fill hard-risk-cap recomputation, async-fill correlation)
      // DOES need this deal's own specific fields, so it is still guarded
      // by a successful select -- only the account-equity-only check above
      // is exempt.
      //
      // **Fixed, 2026-07-28 (Codex review finding, tenth round, P0 finding
      // 3):** a select failure previously returned immediately here,
      // silently skipping the mandatory post-fill hard-risk-cap check
      // entirely -- even though this handler only runs on a genuine
      // DEAL_ADD transaction (SOME deal just fired, and it may belong to
      // this EA's own magic+symbol). Deal-specific fields (magic, symbol,
      // position_id) cannot be read without a successful select, so the
      // PER-TRADE slippage check below cannot run for this specific fill --
      // but the AGGREGATE total-open-risk check has no such dependency
      // (ComputeOwnMagicOpenRiskCash scans live positions/orders directly,
      // never this deal), so it now runs here as a fail-closed fallback,
      // still catching a breach this exact fill may have caused even
      // though its own per-trade details are unreadable.
      if(!HistoryDealSelect(trans.deal))
        {
         if(!DWB_IsClosurePending(g_symbol, InpMagicNumber))
           {
            double fallback_total_risk_cash;
            bool   fallback_total_readable;
            ComputeOwnMagicOpenRiskCash(fallback_total_risk_cash, fallback_total_readable);
            double fallback_equity = AccountInfoDouble(ACCOUNT_EQUITY);
            bool fallback_breached = !fallback_total_readable ||
                                      (fallback_equity > 0.0 &&
                                       100.0 * fallback_total_risk_cash / fallback_equity >
                                       InpRiskCapPercent + 1e-6);
            if(fallback_breached)
              {
               string fallback_breach_reasons[];
               bool fallback_closed = DWB_AttemptClosure(g_symbol, InpMagicNumber,
                                                          fallback_breach_reasons);
               PrintFormat("ThembaEA: CRITICAL -- HistoryDealSelect(#%I64u) failed on a DEAL_ADD "
                           "event; per-trade slippage risk cannot be verified for this fill, but "
                           "the aggregate total-open-risk fallback check found a breach "
                           "(total_readable=%s) -- closure %s.", trans.deal,
                           fallback_total_readable ? "true" : "false",
                           fallback_closed ? "completed" : "pending (will retry every tick)");
              }
           }
         return;
        }

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

      // **Fixed, 2026-07-22 (Codex review finding, seventh round, P1 finding
      // 14): DEAL_ENTRY_INOUT (a reversal -- one deal that closes the
      // existing position AND opens a new one in the opposite direction)
      // was previously ignored entirely here, so neither the cooldown P/L
      // ledger nor position-state cleanup ever saw it. This EA's own
      // no-add-on/no-concurrent-position gate (AttemptOrderSubmission)
      // never produces a reversal under its own magic, but a foreign
      // EA/manual reversal sharing this magic+symbol is still possible in
      // principle -- treating it identically to an ordinary close is
      // correct from THIS position's own perspective (its exposure did
      // end here), matching TradeHistoryAggregator.mqh's own P0 finding 9
      // treatment of the same deal type.**
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
        {
         if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagicNumber &&
            HistoryDealGetString(trans.deal, DEAL_SYMBOL) == g_symbol)
           {
            // **Fixed, 2026-07-22 (Codex review finding, seventh round, P1
            // finding 14): DEAL_FEE was previously omitted from the
            // cooldown P/L figure -- a real fee-bearing closing deal
            // understated its own true net loss/gain, which could change
            // whether CDM_ShouldTriggerCooldown's own "all 3 losses AND
            // sum negative" test fires.**
            double closing_deal_pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                                       HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                                       HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                                       HistoryDealGetDouble(trans.deal, DEAL_FEE);
            ulong closed_position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

            // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1
            // finding 13): every OUT/OUT_BY/INOUT deal was previously
            // recorded as its OWN separate closed trade for the 3-loss
            // cooldown, even when the position remained open afterward (a
            // broker-side partial close of this EA's own "close the full
            // position" request). Three partial losing fills from ONE
            // position could therefore count as three consecutive losses.
            // Each closing deal's own P/L is now ACCUMULATED per position_id
            // (CDM_AccumulatePositionPnl) and only recorded as ONE closed
            // trade once the position is CONFIRMED fully gone below --
            // matching the exact same "only clear/finalize once confirmed"
            // discipline already used for PositionStateTracker/
            // NoStopGraceManager's own per-position state.**
            if(closed_position_id != 0)
              {
               if(!CDM_AccumulatePositionPnl(closed_position_id, closing_deal_pnl))
                  PrintFormat("ThembaEA: CooldownManager failed to accumulate a partial "
                              "closing deal's P/L for position_id=%I64u -- the eventual "
                              "cooldown P/L figure for this position may be understated.",
                              closed_position_id);
              }

            // **Fixed, 2026-07-22 (Codex review finding, seventh round, P1
            // finding 14): a closing deal does not always mean the
            // position is genuinely gone -- a broker-side partial fill of
            // this EA's own "close the full position" request (the same
            // partial-fill phenomenon TradeHistoryAggregator.mqh's own P0
            // finding 9 fix already handles on the entry side) can leave
            // a smaller remainder still open under the SAME position_id.
            // Clearing PositionStateTracker.mqh's own per-position exit
            // state (trailing-stop history, break-even/profit-lock armed
            // flags) while a remainder is still open would silently
            // discard that history for the position's own remaining
            // life. Only clear it once the position is CONFIRMED gone.**
            if(closed_position_id != 0)
              {
               if(!PositionStillOpenById(closed_position_id))
                 {
                  // **Added, 2026-07-22 (Codex review finding, eighth round,
                  // P1 finding 13): the accumulated per-position P/L (every
                  // partial closing deal summed) PLUS this position's own
                  // entry-side commission/fee is what gets recorded as ONE
                  // closed trade for the cooldown, only now that the
                  // position is confirmed fully gone -- see
                  // FinalizeClosedPosition's own header (factored out,
                  // Codex round-10 P1 finding 8, so
                  // ReconcilePendingCloseFinalizations below can share it).**
                  FinalizeClosedPosition(closed_position_id);
                 }
               else
                 {
                  // **Added, 2026-07-28 (Codex review finding, tenth round,
                  // P1 finding 8):** MT5 does not guarantee that every
                  // transaction type for a single close arrives in an order
                  // that makes the position absent from PositionsTotal() at
                  // this exact callback -- a closing deal was JUST observed,
                  // but the live position list has not caught up yet. The
                  // previous code silently skipped finalization here
                  // FOREVER (no other path ever revisited it). Now marks a
                  // durable obligation that ReconcilePendingCloseFinalizations
                  // (called every tick/timer) completes once the position
                  // list catches up, independent of this callback's own
                  // timing.
                  if(!PCF_MarkPendingFinalization(closed_position_id))
                     PrintFormat("ThembaEA: CRITICAL -- failed to persist a pending-finalization "
                                 "mark for position_id=%I64u (still appears open at this exact "
                                 "callback) -- ReconcilePendingCloseFinalizations will not find it "
                                 "if this process crashes before a later successful mark.",
                                 closed_position_id);
                 }
              }

            // **Stated, 2026-07-22 (Codex review finding, eighth round, P1
            // finding 13): DEAL_ENTRY_INOUT is a "reversal" -- one deal that
            // both closes the existing position AND opens a NEW opposite-
            // direction position under a different position_id. This EA now
            // REQUIRES a hedging-mode account (round 8's own P0 finding 1) --
            // and a reversal is structurally a NETTING-account concept (a
            // hedging account cannot net an opposing trade into an existing
            // position; an opposing order simply opens a SEPARATE coexisting
            // position instead). DEAL_ENTRY_INOUT should therefore be
            // unreachable in practice under this EA's own enforced account
            // mode; if a broker nonetheless ever reports one, the closed leg
            // above is still handled correctly (this position's own exposure
            // did end here), and the new leg needs no special initialization
            // -- PositionStateTracker.mqh's own PST_Load already defaults
            // every field safely (peak_r=0, nothing armed) for any
            // position_id it has never seen written, which is the exact
            // correct starting state for a genuinely new position.**
           }
         return;
        }

      if(entry == DEAL_ENTRY_IN)
        {
         // **Added, 2026-07-27 (Codex review finding, ninth round, P0
         // finding 1): recompute THIS fill's own ACTUAL risk (real fill
         // price, real stop, real volume, including adverse entry
         // slippage: abs(actual_fill - stop) * actual_volume * tick_value
         // / tick_size, per the review's own suggested formula) and this
         // magic's real total open risk, forcing a mandatory closure if
         // either now exceeds InpRiskCapPercent. Every gate before this
         // point (gate 4/5b in AttemptOrderSubmission) can only check a
         // pre-fill ESTIMATE -- a real broker fill can land at a worse
         // price than requested, and this is the only point that can
         // catch the resulting REAL breach. Reuses
         // DailyWeeklyBreachManager.mqh's own DWB_AttemptClosure (closes
         // every own-magic position, cancels every own-magic pending
         // order) -- the corrective action for a risk-cap breach is
         // identical to a daily/weekly breach's, so this shares that
         // module's persisted closure_pending flag/retry-until-closed
         // machinery rather than duplicating it under a second name.**
         if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagicNumber &&
            HistoryDealGetString(trans.deal, DEAL_SYMBOL) == g_symbol &&
            !DWB_IsClosurePending(g_symbol, InpMagicNumber))
           {
            ulong opened_position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
            // **Fixed, 2026-07-28 (Codex review finding, tenth round, P0
            // finding 3): DEAL_POSITION_ID is the durable POSITION_IDENTIFIER,
            // not guaranteed to equal the current POSITION_TICKET
            // PositionSelectByTicket() actually expects (see
            // OrderManager.mqh's own SOrderOpenResult header for the exact
            // divergence conditions) -- OM_FindPositionByIdentifier resolves
            // this correctly by enumerating and matching POSITION_IDENTIFIER
            // explicitly, leaving the match selected on success.**
            ulong opened_position_ticket;
            bool position_found = OM_FindPositionByIdentifier(opened_position_id,
                                                                opened_position_ticket);
            bool   per_trade_breached;
            bool   total_breached;
            double actual_trade_risk_cash = 0.0;
            double total_risk_cash = 0.0;
            bool   total_readable = false;
            double equity_now = AccountInfoDouble(ACCOUNT_EQUITY);

            if(!position_found)
              {
               // **Fixed, 2026-07-28 (Codex round-10 P0 finding 3):** a
               // DEAL_ENTRY_IN fill JUST reported this exact position_id --
               // failing to find it now means its own actual risk cannot be
               // verified. The previous code had NO else branch here at all,
               // silently skipping BOTH the per-trade and total checks.
               // Fail closed: treat as breached regardless of what the
               // (unreachable, since the position can't be selected) total
               // check would have found.
               per_trade_breached = true;
               total_breached = true;
              }
            else
              {
               double pos_sl = PositionGetDouble(POSITION_SL);
               bool   pos_is_long = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
               per_trade_breached = false;

               // A stopless position is priced by ComputeOwnMagicOpenRiskCash's
               // own no-SL worst-case fallback below (via the total-risk
               // check), not by this per-trade slippage formula, which needs
               // a real stop to measure a loss distance against.
               if(pos_sl != 0.0)
                 {
                  CSymbolProfile fill_profile;
                  if(fill_profile.Load(g_symbol) && fill_profile.tick_size > 0.0 && equity_now > 0.0)
                    {
                     double actual_fill_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                     double actual_volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
                     // **Fixed, 2026-07-28 (Codex round-10 P0 finding 3): the
                     // spec requires the DIRECTIONAL loss-side distance
                     // (max(0, loss-side distance)), not abs(fill - SL) --
                     // for a BUY filled below an SL that adverse slippage
                     // pushed onto the PROFIT side (SL below entry), abs()
                     // would invent a large "risk" figure and could force a
                     // false emergency closure.**
                     double slippage_loss_distance = pos_is_long
                                                       ? MathMax(0.0, actual_fill_price - pos_sl)
                                                       : MathMax(0.0, pos_sl - actual_fill_price);
                     actual_trade_risk_cash = slippage_loss_distance * actual_volume *
                                              fill_profile.tick_value_loss / fill_profile.tick_size;

                     // **Added, 2026-07-28 (Codex round-10 P0 finding 3):**
                     // RISK_POLICY.md's blanket "use OrderCalcProfit to
                     // cross-check risk" rule applies to every binding risk-
                     // cash computation -- this post-fill figure is exactly
                     // that (it can trigger a real forced closure), and
                     // previously had no cross-check at all. A cross-check
                     // failure or excessive discrepancy fails closed (cannot
                     // vouch for this fill's own actual risk), matching the
                     // pre-submission RM_CrossCheckRiskCash usage in
                     // AttemptOrderSubmission.
                     double broker_risk_cash;
                     bool cross_ok = RM_CrossCheckRiskCash(g_symbol, pos_is_long, actual_volume,
                                                            actual_fill_price, pos_sl,
                                                            actual_trade_risk_cash, broker_risk_cash,
                                                            InpRiskCrossCheckTolerancePercent);
                     if(!cross_ok)
                        per_trade_breached = true; // fail closed -- see comment above
                     else
                       {
                        double actual_trade_risk_percent = 100.0 * actual_trade_risk_cash / equity_now;
                        per_trade_breached = actual_trade_risk_percent > InpRiskCapPercent + 1e-6;
                       }
                    }
                  else
                     per_trade_breached = true; // cannot verify this fill's own actual risk -- fail closed
                 }

               ComputeOwnMagicOpenRiskCash(total_risk_cash, total_readable);
               total_breached = !total_readable ||
                                 (equity_now > 0.0 &&
                                  100.0 * total_risk_cash / equity_now > InpRiskCapPercent + 1e-6);
              }

            if(per_trade_breached || total_breached)
              {
               string breach_reasons[];
               bool breach_closed = DWB_AttemptClosure(g_symbol, InpMagicNumber, breach_reasons);
               PrintFormat("ThembaEA: POST-FILL hard-risk-cap breach for position_id=%I64u "
                           "(position_found=%s, per_trade_breached=%s total_breached=%s, "
                           "actual_trade_risk_cash=%.2f, total_risk_cash=%.2f, "
                           "total_risk_readable=%s) -- closure %s.",
                           opened_position_id, position_found ? "true" : "false",
                           per_trade_breached ? "true" : "false",
                           total_breached ? "true" : "false", actual_trade_risk_cash,
                           total_risk_cash, total_readable ? "true" : "false",
                           breach_closed ? "completed" : "pending (will retry every tick)");
              }
           }

         string pending_signal_id;
         int pending_index;
         string pending_reservation_key;
         bool   pending_was_scalp_mode;
         if(AFC_FindPending(trans.order, pending_signal_id, pending_index, pending_reservation_key,
                             pending_was_scalp_mode))
           {
            ulong resolved_position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
            // Captured before any IM_ClearIntent below -- IM_GetIntentId reads
            // the persisted timestamp/intent_micro fields, which IM_ClearIntent
            // does not wipe (it only zeroes the "active" flag), so this is
            // correct whether read before or after the clear; captured first
            // here purely for clarity of intent (no pun intended).
            string resolved_intent_id = IM_GetIntentId(g_symbol, InpMagicNumber);

            // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0
            // finding 4): the FIRST DEAL_ENTRY_IN deal on a PLACED order
            // previously removed the correlator record and cleared the
            // intent unconditionally -- but under ORDER_FILLING_RETURN, a
            // partial fill can leave the SAME order ticket still working
            // for its unfilled remainder. Clearing everything on the FIRST
            // partial deal left any LATER deal on that same order with no
            // pending record to correlate against. Only treat this as
            // definitively terminal when the order is no longer in the
            // active orders list (OrderSelect fails) -- a real remainder
            // keeps both the correlator entry and the durable intent alive
            // for the next deal on this same order ticket.**
            bool live_remainder = OrderSelect(trans.order);
            if(live_remainder)
              {
               PrintFormat("ThembaEA: async fill for order #%I64u (position_id=%I64u) still has a "
                           "live order remainder -- correlator entry and durable intent left ACTIVE "
                           "pending its own later resolution.", trans.order, resolved_position_id);
              }
            else
              {
               AFC_RemovePending(pending_index);
               // Definitive terminal resolution -- safe to clear the durable
               // intent now (see AttemptOrderSubmission's own step 7 comment
               // for why it was deliberately left active until this point).
               IM_ClearIntent(g_symbol, InpMagicNumber);
               // **Added, 2026-07-27 (Codex round-9 P0 finding 1):** the
               // reservation this fill's own submission made is released here
               // too -- real exposure now exists and is counted by
               // ComputeOwnMagicOpenRiskCash() itself, so continuing to hold
               // the reservation on top of that would double-count this
               // exact risk against the cap.
               RRM_ReleaseReservation(pending_reservation_key);
               // **Added, 2026-07-28 (Codex review finding, tenth round, P1
               // finding 8):** persists THIS position's own entry-time
               // intraday_mode, mirroring AttemptOrderSubmission's own
               // synchronous-fill capture (see that function's own comment)
               // -- previously only the synchronous branch did this, so an
               // asynchronously-opened position silently fell back to the
               // global InpTimeStopUsesScalpMode input for its own exit
               // management instead of the real mode active when it opened.
               if(resolved_position_id != 0)
                 {
                  SPositionExitState async_entry_state = PST_Load(resolved_position_id);
                  async_entry_state.entry_mode_captured = true;
                  async_entry_state.entry_was_scalp_mode = pending_was_scalp_mode;
                  if(!PST_Save(resolved_position_id, async_entry_state))
                     PrintFormat("ThembaEA: failed to persist entry-time intraday_mode for "
                                 "asynchronously-resolved position_id=%I64u -- its own time-stop "
                                 "will fall back to the global InpTimeStopUsesScalpMode input "
                                 "instead.", resolved_position_id);
                 }
              }
            LogAsyncFillResolution(pending_signal_id, resolved_intent_id, true, resolved_position_id,
                                    trans.order, trans.deal,
                                    live_remainder ? "ASYNC_FILL_LIVE_REMAINDER"
                                                    : "ASYNC_FILL_CONFIRMED",
                                    "async_fill_confirmed");
           }
        }
      return;
     }

   if(trans.type == TRADE_TRANSACTION_HISTORY_ADD)
     {
      string pending_signal_id;
      int pending_index;
      string pending_reservation_key;
      bool   pending_was_scalp_mode;
      if(AFC_FindPending(trans.order, pending_signal_id, pending_index, pending_reservation_key,
                          pending_was_scalp_mode))
        {
         ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(trans.order, ORDER_STATE);
         // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding
         // 4): 'state != ORDER_STATE_FILLED' previously treated EVERY
         // non-FILLED final state identically to "never filled" -- but an
         // order that partially filled (real exposure created) and was then
         // cancelled (its unfilled remainder) also ends in a non-FILLED
         // state (CANCELED/EXPIRED), not FILLED. ORDER_POSITION_ID is MT5's
         // own documented link from an order to the position it opened or
         // added to -- nonzero here proves real exposure exists regardless
         // of this order's own final state, and is checked BEFORE trusting
         // the final-state-only signal.**
         ulong order_position_id = (ulong)HistoryOrderGetInteger(trans.order, ORDER_POSITION_ID);
         bool  any_volume_filled = (state == ORDER_STATE_FILLED) || (order_position_id != 0);
         string resolved_intent_id = IM_GetIntentId(g_symbol, InpMagicNumber);

         if(!any_volume_filled)
           {
            AFC_RemovePending(pending_index);
            IM_ClearIntent(g_symbol, InpMagicNumber); // cancelled/expired/rejected -- terminal
            // No exposure was ever created -- release this submission's own
            // risk reservation (Codex round-9 P0 finding 1).
            RRM_ReleaseReservation(pending_reservation_key);
            LogAsyncFillResolution(pending_signal_id, resolved_intent_id, false, 0, trans.order, 0,
                                    "ASYNC_NEVER_FILLED",
                                    StringFormat("async_order_never_filled_state_%s",
                                                  EnumToString(state)));
           }
         else
           {
            // Real exposure exists (a partial fill occurred before this
            // order's own remainder was cancelled/expired). Definitively
            // terminal now -- the order itself is fully done, no live
            // remainder can remain (see the DEAL_ENTRY_IN handler's own
            // OrderSelect check, which is what would have kept this pending
            // record alive this long in the first place).
            AFC_RemovePending(pending_index);
            IM_ClearIntent(g_symbol, InpMagicNumber);
            RRM_ReleaseReservation(pending_reservation_key);
            // **Added, 2026-07-28 (Codex review finding, tenth round, P1
            // finding 8):** this path is reached only when the DEAL_ENTRY_IN
            // handler above left the pending record ACTIVE (a live
            // remainder existed at that time, so it deliberately did NOT
            // capture entry-mode yet -- see that handler's own comment) and
            // the remainder has now been cancelled/expired -- entry-mode
            // was never captured for this position at all until now.
            SPositionExitState history_entry_state = PST_Load(order_position_id);
            if(!history_entry_state.entry_mode_captured)
              {
               history_entry_state.entry_mode_captured = true;
               history_entry_state.entry_was_scalp_mode = pending_was_scalp_mode;
               if(!PST_Save(order_position_id, history_entry_state))
                  PrintFormat("ThembaEA: failed to persist entry-time intraday_mode for "
                              "position_id=%I64u (resolved via HISTORY_ADD) -- its own time-stop "
                              "will fall back to the global InpTimeStopUsesScalpMode input "
                              "instead.", order_position_id);
              }
            ulong fill_deal_ticket = FindFillDealForOrder(trans.order);
            LogAsyncFillResolution(pending_signal_id, resolved_intent_id, true, order_position_id,
                                    trans.order, fill_deal_ticket,
                                    "ASYNC_PARTIAL_FILL_THEN_CANCELLED",
                                    StringFormat("async_order_partial_fill_then_%s",
                                                  EnumToString(state)));
           }
        }
      return;
     }
  }

void OnDeinit(const int reason)
  {
   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 10):
   // pairs with OnInit's own EventSetTimer(30) -- MT5 requires a matching
   // EventKillTimer, and leaving the timer running past this EA's own
   // lifetime would fire OnTimer against globals/state no longer valid for
   // this chart attachment.**
   EventKillTimer();
   PrintFormat("ThembaEA: deinitialized, reason=%d.", reason);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 10):** the no-tick-boundary guarantee -- fires on its own 30-second           |
//| wall-clock schedule (EventSetTimer, armed in OnInit) regardless of              |
//| whether any price tick arrives, so the mandatory intraday close is                |
//| attempted even through a tick-starved period spanning the boundary. Uses             |
//| the SAME persisted-due/pending reconciliation OnTick and OnInit both use,                |
//| so a close armed here and one armed from a tick are the same record, never                  |
//| double-tracked.                                                                                 |
//|                                                                    |
//| **Extended, 2026-07-28 (Codex review finding, tenth round, P0 finding    |
//| 6):** previously the ONLY wall-clock mandatory protection driven from        |
//| this timer was the intraday close -- the five-second no-stop grace-period          |
//| closure and the daily/weekly/total-risk mandatory closure re-evaluation                |
//| were driven from OnTick alone, so a stopless position (or an unresolved                    |
//| breach) could remain untracked/open indefinitely during a genuinely tick-                       |
//| starved interval, despite the specification's wall-clock maximums. Every                            |
//| wall-clock mandatory protection this EA has now runs from BOTH OnTick AND                                this
//| timer.**                                                                                                     |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ICM_ReconcileIntradayClose(g_symbol, InpMagicNumber, InpIntradayBoundaryHour,
                               InpIntradayBoundaryMinute);
   ReEvaluateMandatoryClosureObligations();
   EnforceNoStopGracePeriod();
   // **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding 8):
   // same tick-starved-fallback rationale as the other wall-clock
   // protections above -- see ReconcilePendingCloseFinalizations's own
   // header.**
   ReconcilePendingCloseFinalizations();
   // **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding 9):
   // ChartPatternLifecycle.mqh's own CPL_CleanupStale existed with no
   // production caller at all -- wired here so GlobalVariable count for
   // consumed/expired pattern instances stays bounded over the EA's
   // lifetime instead of growing forever. A 7-day retention window is
   // deliberately generous relative to InpPatternMaxAgeBars' own bar-count
   // horizon (a handful of hours on any realistic timeframe) -- this is a
   // housekeeping bound, not an operational one.
   CPL_CleanupStale(g_symbol, InpMagicNumber, 7 * 86400);
  }

void OnTick()
  {
   // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 6):
   // retry arming the no-tick-boundary timer every tick until it succeeds --
   // see OnInit's own comment for why EventSetTimer's return value must not
   // be discarded. A cheap, idempotent registration call; harmless to retry
   // even if the underlying cause of an earlier failure has not changed.
   if(!g_timer_armed)
      g_timer_armed = EventSetTimer(30);

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
   // until ICM_ReconcileIntradayClose reports a fully broker-confirmed
   // success (see IntradayCloseManager.mqh's own P0 finding 8/10 fixes).
   //
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 10):
   // now delegates to ICM_ReconcileIntradayClose (persisted, restart- and
   // midnight-rollover-durable due/pending tracking) instead of
   // ICM_ShouldExecuteIntradayClose/ICM_ExecuteIntradayClose's own in-memory-
   // only guard, and uses the real InpIntradayBoundaryHour/Minute operator
   // inputs instead of a hard-coded function-argument default. See
   // IntradayCloseManager.mqh's own header for the full gap this closes: a
   // close that was still owed when the calendar rolled over to a new day
   // could previously be silently dropped (the next day's own boundary check
   // reads false until ITS OWN 23:45 arrives), leaving overnight exposure
   // open indefinitely.**
   ICM_ReconcileIntradayClose(g_symbol, InpMagicNumber, InpIntradayBoundaryHour,
                               InpIntradayBoundaryMinute);

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 3):
   // retry-until-closed for a daily/weekly loss-cap breach closure -- per
   // section 8, "if the close fails (requote/error), the EA retries on
   // every subsequent tick until confirmed closed." A fresh breach is armed
   // from OnTradeTransaction (the required synchronous, same-handler
   // submission).
   //
   // **Fixed, 2026-07-28 (Codex review findings, tenth round, P0 findings 6
   // and 7):** previously only re-attempted a closure ALREADY marked
   // pending -- now delegates to ReEvaluateMandatoryClosureObligations(),
   // which ALSO re-derives the breach condition from ground truth
   // (current daily/weekly baselines, current total open risk) when
   // nothing is currently marked pending, so a closure obligation whose own
   // persisted flag never survived a prior crash, or an unreadable
   // daily/weekly state, is rediscovered here every tick instead of only
   // ever being caught by a fresh OnTradeTransaction detection. Also called
   // from OnTimer (tick-starved fallback) and OnInit (restart) -- see that
   // function's own header.**
   ReEvaluateMandatoryClosureObligations();

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 3):
   // section 8's no-SL fallback mandatory-remediation grace period -- runs
   // every tick so a position that has been stopless for
   // >= InpNoStopGraceSeconds is closed immediately (fail-closed), not just
   // priced into ComputeOwnMagicOpenRiskCash's own risk figure.**
   EnforceNoStopGracePeriod();

   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 5):
   // re-runs durable-intent reconciliation every tick while an intent
   // remains active -- see ReconcileIntentAndFeedAFC's own header for why a
   // single OnInit call is not always sufficient (a too-young-to-conclude
   // intent needs a later re-check to age past InpIntentTimeoutSeconds; a
   // just-discovered pending order needs its AsyncFillCorrelator record
   // reconstructed before the normal fill/cancel path can resolve it).
   // Cheap no-op via IM_HasActiveIntent's own single GlobalVariableGet
   // whenever no intent is outstanding, which is the steady-state case.**
   ReconcileIntentAndFeedAFC();

   // **Added, 2026-07-28 (Codex review finding, tenth round, P1 finding 8):
   // re-checks every position_id marked as awaiting close-finalization
   // (its own closing deal was seen, but the live position list had not
   // caught up yet at that exact callback) -- see
   // ReconcilePendingCloseFinalizations's own header. Cheap no-op via
   // PCF_FindPendingFinalizations' own prefix-scan whenever nothing is
   // pending, the steady-state case.**
   ReconcilePendingCloseFinalizations();

   // **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding 8):
   // a persistent post-boundary entry lock. SN_IsPastIntradayBoundary() is a
   // pure function of the current server clock, so this needs no
   // restart-durable flag: it is true on every tick past today's boundary
   // regardless of whether the EA (re)started mid-day, and it naturally
   // resets to false at the next server midnight without any date-tracking
   // of its own. This closes the gap where a fully successful close (which
   // suppresses further CLOSE attempts for the rest of the day via
   // g_icm_close_done_today) left no gate blocking a later bar's NEW entry
   // after the boundary had already passed.
   //
   // **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding
   // 10): now uses the real InpIntradayBoundaryHour/Minute operator inputs,
   // and ALSO blocks on ICM_IsCloseReconciliationPending -- a still-owed
   // close carried over from an EARLIER day (the calendar has already rolled
   // to a new day, so SN_IsPastIntradayBoundary() alone now reads false
   // again) must keep blocking new entries just as much as TODAY's own
   // not-yet-resolved boundary does; this is exactly the persisted-due/
   // pending record IntradayCloseManager.mqh's own header describes.**
   bool past_intraday_boundary = SN_IsPastIntradayBoundary(InpIntradayBoundaryHour,
                                                             InpIntradayBoundaryMinute) ||
                                  ICM_IsCloseReconciliationPending(g_symbol, InpMagicNumber);

   // **Moved, 2026-07-22 (Codex review finding, eighth round, P0 finding 4):
   // equity-peak tracking now runs on EVERY tick -- previously these only
   // ran from EvaluateAndJournal's own once-per-completed-bar path, so a
   // large intrabar move that reverted before the bar closed was never
   // captured in either peak, understating both the daily giveback and the
   // all-time drawdown section 8's own downstream risk controls depend on.
   //
   // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 2):
   // this previously discarded both return values with the reasoning "a
   // single tick's lock-timeout failure self-heals on the very next tick" --
   // true for THIS tick's own peak update, but EvaluateAndJournal's
   // drawdown-based risk-multiplier gate (section 3) runs on THIS SAME
   // tick's decision path when this is also a completed-bar tick, and it
   // was reading whatever peak happened to already be persisted with no
   // way to know this tick's own update had just failed -- an unlucky
   // lock-timeout on exactly a decision bar silently let drawdown-based
   // risk reduction fall through to "no reduction" instead of "unknown,
   // block". g_peak_state_valid now makes that failure visible to this
   // same bar's own gate, not just self-healing invisibly next tick.**
   bool daily_peak_ok   = EPM_UpdateDailyPeak();
   bool account_peak_ok = EPM_UpdateAccountPeak();
   g_peak_state_valid = daily_peak_ok && account_peak_ok;

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

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, seventh round, P1 finding    |
//| 18):** signal_id was symbol + broker SECOND (TimeCurrent(), no sub-        |
//| second resolution) + a process-local counter that resets to 0 on every       |
//| restart -- two concurrent instances of this EA (e.g. different magic          |
//| numbers on the same symbol) or a fast restart within the same wall-clock         |
//| second could produce an IDENTICAL signal_id, silently colliding in the             |
//| journal (and in any downstream join keyed on it). GetMicrosecondCount()               |
//| returns microseconds since the TERMINAL's own start (shared across every               |
//| EA instance in this terminal, monotonically increasing within a session),               |
//| combined with 'magic' (distinguishes concurrent DIFFERENT-strategy                        |
//| instances even on the same symbol/second) makes an actual collision                          |
//| astronomically unlikely, replacing the previous single shared, duplicated                       |
//| format string at both call sites with one function.                                                |
//+------------------------------------------------------------------+
string BuildSignalId(const string symbol, const long magic)
  {
   g_signal_counter++;
   return StringFormat("%s_%I64d_%I64d_%I64u_%I64d", symbol, magic, (long)TimeCurrent(),
                        GetMicrosecondCount(), g_signal_counter);
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
//| Best-effort current ATR for an arbitrary symbol (which may not be the  |
//| chart symbol g_md is bound to), matching the Export_*.mq5 scripts' own    |
//| iATR+CopyBuffer convention -- used only by the no-SL fallback below,          |
//| where the stopless position may live on a different symbol than this              |
//| instance's own g_symbol (own-magic risk is summed across every symbol,               |
//| per this function's own header).                                                         |
//+------------------------------------------------------------------+
bool GetCurrentATRForSymbol(const string symbol, const ENUM_TIMEFRAMES timeframe,
                             const int period, double &atr)
  {
   atr = 0.0;
   int handle = iATR(symbol, timeframe, period);
   if(handle == INVALID_HANDLE)
      return false;
   double buf[];
   ArraySetAsSeries(buf, true);
   bool ok = CopyBuffer(handle, 0, 0, 1, buf) > 0;
   IndicatorRelease(handle);
   if(!ok)
      return false;
   atr = buf[0];
   return atr > 0.0;
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
//| **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding      |
//| 3):** a position with no stop (POSITION_SL == 0) now applies section 8's          |
//| no-SL fallback (`risk_cash_no_stop = ATR * InpNoStopWorstCaseATRMultiple *              |
//| volume * tick_value / tick_size`) instead of being skipped -- skipping                       |
//| understated total own-magic exposure whenever a stopless position existed                       |
//| (EnforceNoStopGracePeriod, called every tick from OnTick, is what actually                          |
//| CLOSES a stopless position once InpNoStopGraceSeconds elapses; this                                    |
//| function only prices the risk it represents while it exists). Also now                                    |
//| sums the worst-case risk_cash of every own-magic PENDING order,                                              |
//| UNCONDITIONALLY (never max-of-two) -- per section 8's own correction: a                                        |
//| hedging-only account allows opposite pending orders to BOTH independently                                          |
//| fill and coexist, so there is no "only one can fill" assumption to justify                                            |
//| taking the larger of two figures instead of their sum. A stopless pending                                                 |
//| order is skipped here too (defensive completeness only -- the mandatory-                                                     |
//| stop rule at submission should make this unreachable in practice).**                                                            |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 1):     |
//| this previously returned a bare double, silently treating "position/       |
//| order risk could not be priced" identically to "genuinely zero risk"          |
//| -- a symbol profile that fails to load, ATR unavailable for a stopless           |
//| position, RM_Compute*RiskCash itself failing, or a stopless PENDING                  |
//| order (genuinely unbounded risk if it fills; the mandatory-stop rule                    |
//| SHOULD make this unreachable, but this function must not silently                          |
//| trust that invariant) all now mark the WHOLE scan invalid, not just                            |
//| skip their own contribution. 'all_readable_out' is false whenever ANY                              |
//| component's risk could not be verified -- callers MUST treat that as                                   |
//| "cannot verify headroom" and fail closed (refuse the new entry), never                                    |
//| trade on the partial total 'risk_cash_out' still reports for                                              |
//| diagnostic logging. A position/order whose stop is genuinely on the                                       |
//| non-loss side (a real, legitimately zero-risk state                                                       |
//| RM_ComputeLossDistance's own documented contract already returns 0.0                                      |
//| for) is NOT treated as invalid -- only genuinely unreadable/unpriceable                                   |
//| states are.**                                                                                             |
//|                                                                    |
//| **Fixed, 2026-07-28 (Codex review finding, tenth round, P0 finding 3):    |
//| a zero ticket from PositionGetTicket()/OrderGetTicket() at a valid              |
//| enumeration index now fails closed (was previously silently skipped as             |
//| if that slot held no position/order at all -- see the loops' own                       |
//| comments). Every real-SL risk-cash figure (position or pending order) is                    |
//| now cross-checked against OrderCalcProfit (RISK_POLICY.md's blanket                             |
//| rule), matching the same discipline AttemptOrderSubmission's own pre-                               |
//| submission RM_CrossCheckRiskCash call already applies -- a cross-check                                 |
//| failure or excessive discrepancy fails closed. The no-SL ATR-proxy                                          |
//| worst-case branch is deliberately NOT cross-checked (it is an explicit                                          |
//| estimate with no real price level for OrderCalcProfit to value against).**                                          |
//+------------------------------------------------------------------+
bool ComputeOwnMagicOpenRiskCash(double &risk_cash_out, bool &all_readable_out)
  {
   double total = 0.0;
   bool   all_readable = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
        {
         // **Fixed, 2026-07-28 (Codex round-10 P0 finding 3):** a zero ticket
         // at a valid enumeration index (0..PositionsTotal()-1) is a
         // TRANSIENT read failure (the live position list changed between
         // the PositionsTotal() call and this PositionGetTicket() call --
         // documented MT5 API behavior, not "no position here": a genuinely
         // empty slot is never enumerated at all). Silently skipping it
         // (the previous behavior) undercounted real risk exactly like every
         // other unreadable-component case this scan already fails closed
         // on below.
         all_readable = false;
         continue;
        }
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      bool pos_is_long = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      CSymbolProfile pos_profile;
      if(!pos_profile.Load(pos_symbol))
        {
         all_readable = false; // symbol profile unreadable -- risk unknown, not zero
         continue;
        }

      double sl = PositionGetDouble(POSITION_SL);
      double risk_cash;
      if(sl == 0.0)
        {
         double atr;
         if(!GetCurrentATRForSymbol(pos_symbol, InpRegimeTimeframe, 14, atr))
           {
            all_readable = false; // ATR unavailable this tick -- EnforceNoStopGracePeriod
                                   // will still close this position once the grace period
                                   // elapses regardless of whether this pricing succeeds,
                                   // but THIS scan cannot vouch for its risk right now.
            continue;
           }
         if(RM_ComputeNoStopRiskCash(pos_profile, atr, volume, risk_cash,
                                      InpNoStopWorstCaseATRMultiple))
            total += risk_cash;
         else
            all_readable = false;
         continue;
        }

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double loss_distance = pos_is_long ? MathMax(0.0, entry - sl) : MathMax(0.0, sl - entry);
      if(loss_distance <= 0.0)
         continue; // stop genuinely on the non-loss side -- a real zero, not unreadable

      if(RM_ComputeRiskCash(pos_profile, loss_distance, volume, risk_cash))
        {
         // **Added, 2026-07-28 (Codex review finding, tenth round, P0
         // finding 3):** RISK_POLICY.md's blanket OrderCalcProfit cross-
         // check now also applies here -- this figure directly feeds
         // total_breached, a real forced-closure trigger, exactly the kind
         // of "binding risk-cash computation" the policy requires it for.
         // A real SL price exists for this branch (checked above), so a
         // genuine broker valuation is possible, unlike the no-SL ATR-proxy
         // branch above (a deliberate worst-case ESTIMATE with no real
         // price level to check against).
         double broker_risk_cash;
         if(RM_CrossCheckRiskCash(pos_symbol, pos_is_long, volume, entry, sl, risk_cash,
                                   broker_risk_cash, InpRiskCrossCheckTolerancePercent))
            total += risk_cash;
         else
            all_readable = false; // cross-check failed or disagreed beyond tolerance -- fail closed
        }
      else
         all_readable = false;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
        {
         // Same transient-read-failure fix as the positions loop above
         // (Codex round-10 P0 finding 3) -- fail closed, never silently
         // treat as "no order here".
         all_readable = false;
         continue;
        }
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;

      double sl = OrderGetDouble(ORDER_SL);
      if(sl == 0.0)
        {
         // A stopless PENDING order represents genuinely unbounded risk if it
         // fills. The mandatory-stop rule at submission should make this
         // unreachable for this EA's own orders, but this scan must not
         // silently trust that invariant for whatever produced this order.
         all_readable = false;
         continue;
        }

      string ord_symbol = OrderGetString(ORDER_SYMBOL);
      double entry = OrderGetDouble(ORDER_PRICE_OPEN);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool ord_is_long = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
                           type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);

      double loss_distance = ord_is_long ? MathMax(0.0, entry - sl) : MathMax(0.0, sl - entry);
      if(loss_distance <= 0.0)
         continue; // stop genuinely on the non-loss side -- a real zero, not unreadable

      CSymbolProfile ord_profile;
      if(!ord_profile.Load(ord_symbol))
        {
         all_readable = false;
         continue;
        }

      double risk_cash;
      if(RM_ComputeRiskCash(ord_profile, loss_distance, volume, risk_cash))
        {
         // **Added, 2026-07-28 (Codex round-10 P0 finding 3):** same
         // broker-native cross-check as the positions loop above -- see
         // that branch's own comment.
         double broker_risk_cash;
         if(RM_CrossCheckRiskCash(ord_symbol, ord_is_long, volume, entry, sl, risk_cash,
                                   broker_risk_cash, InpRiskCrossCheckTolerancePercent))
            total += risk_cash; // unconditional sum — see header comment
         else
            all_readable = false; // cross-check failed or disagreed beyond tolerance -- fail closed
        }
      else
         all_readable = false;
     }

   risk_cash_out = total;
   all_readable_out = all_readable;
   return all_readable;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 3):** section 8's no-SL fallback mandatory-remediation grace period,     |
//| own-magic scope. Every own-magic position currently missing a stop is       |
//| tracked (NoStopGraceManager.mqh, keyed by its durable position_id); once       |
//| InpNoStopGraceSeconds have elapsed since it was FIRST observed stopless,          |
//| it is closed immediately via OM_ClosePosition (fail-closed, per section              |
//| 8's own wording, not a rejection this EA can defer). A position that              |
//| regains a valid stop (a later ExitOrchestrator/manual action attaches                  |
//| one) or that closes is un-tracked so it is never spuriously flagged                       |
//| again.**                                                                                     |
//+------------------------------------------------------------------+
void EnforceNoStopGracePeriod()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double sl = PositionGetDouble(POSITION_SL);
      if(sl != 0.0)
        {
         NSG_Clear(position_id); // valid stop attached -- stop tracking
         continue;
        }

      datetime first_seen = NSG_GetFirstSeen(position_id);
      if(first_seen == 0)
        {
         first_seen = TimeCurrent();
         NSG_SetFirstSeen(position_id, first_seen);
         continue; // just observed -- grace period starts now, not yet expired
        }

      // **Added, 2026-07-28 (Codex review finding, tenth round, P0 finding
      // 6):** retry the persisted write on EVERY tick/timer fire while it
      // remains unconfirmed, not just once at first observation -- NSG's own
      // in-memory fallback (round-9 P0 finding 6) keeps THIS session's own
      // timing correct even if the persisted write keeps failing, but a
      // crash before that write ever succeeds would lose the obligation on
      // restart (NSG_GetFirstSeen would read 0 again, resetting the clock).
      // GlobalVariableCheck is a cheap read; this only re-attempts the write
      // when the persisted key genuinely does not exist yet, narrowing the
      // restart-survival gap to "at most a few ticks/timer fires", not
      // "forever until restart, then silently reset".
      if(!GlobalVariableCheck(NSG_Key(position_id)))
        {
         if(!NSG_SetFirstSeen(position_id, first_seen))
            PrintFormat("ThembaEA: CRITICAL -- NoStopGraceManager failed to durably persist "
                        "position_id=%I64u's first-seen-stopless timestamp -- the %d-second grace "
                        "obligation is NOT yet restart-survivable for this position; retrying every "
                        "tick/timer.", position_id, InpNoStopGraceSeconds);
        }

      if((TimeCurrent() - first_seen) < InpNoStopGraceSeconds)
         continue; // still within the remediation grace period

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      PrintFormat("ThembaEA: position #%I64u (%s, position_id=%I64u) has had no stop for >= "
                  "%d seconds -- closing immediately (fail-closed, section 8 no-SL grace period).",
                  ticket, pos_symbol, position_id, InpNoStopGraceSeconds);

      string close_rejection_reason;
      if(!OM_ClosePosition(ticket, InpMagicNumber, close_rejection_reason))
         PrintFormat("ThembaEA: no-SL grace-period close attempt for #%I64u failed (%s) -- "
                     "will retry next tick.", ticket, close_rejection_reason);
      // NSG_Clear happens once OnTradeTransaction confirms the position is
      // actually gone (mirrors PST_Clear's own "clear once confirmed" rule,
      // see OnTradeTransaction's DEAL_ENTRY_OUT handling) -- not here, since
      // a requote/error leaves the position still open and still stopless.
     }
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

   //--- 1b. Daily/weekly breach closure still in flight (Codex review -----
   //--- finding, eighth round, P0 finding 3) ------------------------------
   // Per section 8: a breach closure "blocks new entries on that symbol
   // meanwhile" until DWB_AttemptClosure reports every own-magic position
   // closed and every own-magic pending order cancelled.
   if(DWB_IsClosurePending(g_symbol, InpMagicNumber))
     {
      AppendReason(rejected, "daily_weekly_breach_closure_in_progress");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   //--- 2. Daily/weekly loss caps (account-wide measurement) -------------
   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 4):
   // a failed baseline/cash-flow persistence this bar (lock timeout, etc.)
   // must fail closed -- DWL_IsDailyLossBreached/DWL_IsWeeklyLossBreached
   // both return false for "no baseline exists" exactly the same as for
   // "checked and not breached", so trusting them after a KNOWN write
   // failure would silently treat an unknown risk state as safe to trade.**
   if(!g_daily_weekly_risk_state_valid)
     {
      AppendReason(rejected, "daily_weekly_risk_state_persistence_failed");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
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
   // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 2):
   // EPM_GetCurrentDrawdownPercent now reports its own validity separately
   // from "zero drawdown" (see that function's own header) -- an unknown
   // peak state (never recorded, or this bar's own EPM_Update*Peak calls
   // failed to persist, see g_peak_state_valid below) must fail closed
   // exactly like the daily/weekly risk-state gate above it, never fall
   // through to the least-restrictive 1.0x multiplier.**
   if(!g_peak_state_valid)
     {
      AppendReason(rejected, "equity_peak_state_persistence_failed");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   double current_drawdown;
   bool drawdown_valid;
   EPM_GetCurrentDrawdownPercent(current_drawdown, drawdown_valid);
   if(!drawdown_valid)
     {
      AppendReason(rejected, "equity_peak_never_recorded");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
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
   //
   // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 1):**
   // this previously trusted a bare double from ComputeOwnMagicOpenRiskCash
   // (now fail-closed -- see that function's own header) and checked it as an
   // unguarded snapshot, so two chart instances sharing this magic on
   // different symbols could each independently see headroom and both
   // submit, together exceeding the cap. RRM_TryReserve now performs the
   // whole check-then-reserve sequence under ONE account-lock hold
   // (StateManager.mqh's own owner-token lock), summing every OTHER symbol's
   // own live reservation under this same magic before deciding -- see
   // RiskReservationManager.mqh's own header for the full design.
   //
   // **Fixed, 2026-07-28 (Codex review finding, tenth round, P0 finding 2):**
   // ComputeOwnMagicOpenRiskCash's own snapshot was previously taken BEFORE
   // RRM_TryReserve's own lock acquisition -- "actual exposure + reservations
   // + new reservation" was therefore never genuinely one critical section; a
   // position could appear between this snapshot and the (separately locked)
   // reservation decision. The account lock is now acquired HERE, held across
   // the snapshot AND the reservation decision (RRM_TryReserveLocked, which
   // assumes the lock is already held -- see its own header), and released
   // once the decision is made, closing that gap.
   double account_lock_token;
   if(!SM_AcquireAccountLock(account_lock_token))
     {
      AppendReason(rejected, "total_open_risk_lock_timeout");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   double existing_open_risk_cash;
   bool   existing_risk_readable;
   ComputeOwnMagicOpenRiskCash(existing_open_risk_cash, existing_risk_readable);
   if(!existing_risk_readable)
     {
      SM_ReleaseAccountLock(account_lock_token);
      AppendReason(rejected, "total_open_risk_unreadable_failing_closed");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   double total_open_risk_percent;
   string reservation_rejection;
   string reservation_key;
   bool reserved = RRM_TryReserveLocked(g_symbol, InpMagicNumber, existing_open_risk_cash,
                                          sizing.risk_cash_actual, InpRiskCapPercent, equity,
                                          total_open_risk_percent, reservation_rejection,
                                          reservation_key);
   SM_ReleaseAccountLock(account_lock_token);
   if(!reserved)
     {
      AppendReason(rejected, reservation_rejection);
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
      // Codex round-9 P0 finding 1: the reservation gate 5b just made must
      // not be left dangling until its own crash-recovery staleness timeout
      // -- this decision is rejected here, so no submission will ever use it.
      RRM_ReleaseReservation(reservation_key);
      AppendReason(rejected, StringFormat(
         "risk_cross_check_failed_computed_%.4f_broker_%.4f",
         sizing.risk_cash_actual, broker_risk_cash));
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   AppendReason(passed, "risk_cross_check_passed");

   //--- 7. Durable-intent-guarded real order submission (TASK-034) --------
   string intent_id;
   if(!IM_BeginIntent(g_symbol, InpMagicNumber, is_long, sizing.volume, TimeCurrent(), intent_id))
     {
      // An intent is already active — a prior submission on this symbol+magic
      // has not yet been confirmed filled/rejected. Refuse to submit a
      // second order rather than risk a duplicate position.
      // Same reservation-release requirement as the cross-check rejection
      // above (Codex round-9 P0 finding 1).
      RRM_ReleaseReservation(reservation_key);
      AppendReason(rejected, "intent_already_active_refusing_duplicate_submission");
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }

   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 5):
   // the broker comment now carries the durable intent's own unique ID
   // ("TI<microsecond-counter>") instead of "Themba_<strategy>" -- per
   // TASK-002_PHASE2_SPECIFICATION.md section 11's "broker-visible
   // correlation" requirement: this comment is what
   // IM_FindIntentInHistory searches for after a restart, so it must be
   // this exact, unique value, not a human-readable but collision-prone
   // strategy tag. IM_BeginIntent already guarantees intent_id fits well
   // within MT5's 31-character comment limit (see its own header).**
   string comment = intent_id;

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
      // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 4):
      // OM_OpenPosition returning false does NOT always mean the order was
      // rejected -- exposure_unresolved means the broker's own retcode
      // confirmed a REAL fill (DONE/DONE_PARTIAL) but this process could
      // not resolve the fill's own deal/position details. Treating this
      // identically to an outright rejection (the previous behavior) would
      // clear the durable intent and leave real, live exposure completely
      // uncorrelated -- a second decision on the next bar could then submit
      // ANOTHER order for the same symbol+magic on top of it. The intent is
      // left ACTIVE here (never cleared) so IM_BeginIntent's own guard
      // continues refusing a new submission for this symbol+magic until a
      // later reconciliation pass (IM_ReconcileOnRestart, or a subsequent
      // OnTradeTransaction call once the terminal's own history catches up)
      // resolves it. The risk reservation IS released, though -- the real
      // position this fill created will be picked up by
      // ComputeOwnMagicOpenRiskCash()'s own independent PositionsTotal()
      // scan regardless of this process's resolution failure, so continuing
      // to hold the reservation on top of that would double-count it.**
      if(open_result.exposure_unresolved)
        {
         RRM_ReleaseReservation(reservation_key);
         AppendReason(rejected, "order_exposure_unresolved_awaiting_reconciliation_" +
                      open_result.rejection_reason);
         decision.reasons_passed_json = BuildJsonStringArray(passed);
         decision.reasons_rejected_json = BuildJsonStringArray(rejected);
         PrintFormat("ThembaEA: CRITICAL -- OM_OpenPosition confirms broker retcode=%u (a REAL "
                     "fill) but could not resolve this fill's own position details (%s). Live "
                     "exposure may exist at the broker, uncorrelated to this decision. The durable "
                     "intent is left ACTIVE -- no new entry will be attempted for '%s' magic %I64d "
                     "until this is reconciled.",
                     open_result.retcode, open_result.rejection_reason, g_symbol, InpMagicNumber);
         // **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding
         // 9): this is exactly the review's own crash-window scenario -- a
         // broker-confirmed real fill whose own details this process could
         // not resolve. Written here, immediately, rather than waiting for
         // EvaluateAndJournal's later DJ_AppendDecision call (which this
         // rejected decision will never reach with a populated order_id
         // anyway) -- independent, durable evidence that a fill happened,
         // even though position_id/volume/price are genuinely unknown here.
         SExecutionEvent unresolved_evt = EEJ_NewEvent();
         datetime unresolved_time = DJ_ServerTimeToUtc(TimeTradeServer());
         unresolved_evt.event_id = EEJ_BuildEventId(unresolved_time, GetMicrosecondCount());
         unresolved_evt.event_type = "SYNC_FILL_UNRESOLVED";
         unresolved_evt.signal_id = decision.signal_id;
         unresolved_evt.intent_id = intent_id;
         unresolved_evt.order_ticket = open_result.order_ticket;
         if(open_result.deal_ticket != 0)
            unresolved_evt.deal_id = IntegerToString((long)open_result.deal_ticket);
         unresolved_evt.timestamp = unresolved_time;
         unresolved_evt.symbol = g_symbol;
         unresolved_evt.filled = true;
         unresolved_evt.outcome_note = "sync_fill_confirmed_by_retcode_but_details_unresolved_" +
                                        open_result.rejection_reason;
         string unresolved_evt_error;
         if(!EEJ_AppendEvent(unresolved_evt, unresolved_evt_error))
            PrintFormat("ThembaEA: CRITICAL -- failed to append execution-event journal row for "
                        "the unresolved fill above (%s).", unresolved_evt_error);
         return;
        }

      IM_ClearIntent(g_symbol, InpMagicNumber); // rejected outright -- definitively terminal
      RRM_ReleaseReservation(reservation_key); // Codex round-9 P0 finding 1
      AppendReason(rejected, "order_" + open_result.rejection_reason);
      decision.reasons_passed_json = BuildJsonStringArray(passed);
      decision.reasons_rejected_json = BuildJsonStringArray(rejected);
      return;
     }
   if(open_result.position_id != 0)
     {
      // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding
      // 4): a DONE_PARTIAL fill under ORDER_FILLING_RETURN can leave this
      // exact order ticket still WORKING for its unfilled remainder (see
      // SOrderOpenResult's own has_live_remainder comment) -- clearing the
      // intent unconditionally here would let a LATER remainder fill (or
      // cancellation) go completely uncorrelated. When a remainder is
      // still live, the intent is left ACTIVE and this order is registered
      // with AsyncFillCorrelator.mqh (the same mechanism the fully-async
      // PLACED path below already uses) so OnTradeTransaction's normal
      // DEAL_ENTRY_IN/HISTORY_ADD handling resolves it whenever the
      // remainder's own terminal outcome eventually arrives.**
      if(open_result.has_live_remainder)
        {
         // reservation_key deliberately omitted (defaults to "") -- the
         // reservation is released unconditionally just below regardless of
         // this branch (real exposure already exists from the partial fill,
         // which is what the reservation was guarding), so there is nothing
         // left for a later async resolution to release a second time.
         AFC_AddPending(open_result.order_ticket, decision.signal_id);
         PrintFormat("ThembaEA: DONE_PARTIAL fill for position_id=%I64u still has a live order "
                     "remainder (ticket #%I64u) -- durable intent left ACTIVE pending its own "
                     "later resolution.", open_result.position_id, open_result.order_ticket);
        }
      else
        {
         IM_ClearIntent(g_symbol, InpMagicNumber); // synchronous fill confirmed -- definitively terminal
        }
      RRM_ReleaseReservation(reservation_key); // Codex round-9 P0 finding 1 -- real
                                                          // exposure now exists and is counted by
                                                          // ComputeOwnMagicOpenRiskCash() itself.

      // **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding 9):
      // written here, immediately upon synchronous fill confirmation --
      // before EvaluateAndJournal's own later DJ_AppendDecision call, so a
      // crash in between still leaves this independent, durable evidence
      // that the fill happened (the review's own crash-window complaint).**
      SExecutionEvent sync_evt = EEJ_NewEvent();
      datetime sync_evt_time = DJ_ServerTimeToUtc(TimeTradeServer());
      sync_evt.event_id = EEJ_BuildEventId(sync_evt_time, GetMicrosecondCount());
      sync_evt.event_type = open_result.has_live_remainder ? "SYNC_FILL_LIVE_REMAINDER" : "SYNC_FILL";
      sync_evt.signal_id = decision.signal_id;
      sync_evt.intent_id = intent_id;
      sync_evt.order_id = IntegerToString((long)open_result.position_id);
      sync_evt.order_ticket = open_result.order_ticket;
      if(open_result.deal_ticket != 0)
         sync_evt.deal_id = IntegerToString((long)open_result.deal_ticket);
      sync_evt.timestamp = sync_evt_time;
      sync_evt.symbol = g_symbol;
      sync_evt.filled = true;
      sync_evt.volume = open_result.filled_volume;
      sync_evt.has_volume = true;
      sync_evt.price = open_result.fill_price;
      sync_evt.has_price = (open_result.fill_price > 0.0);
      sync_evt.outcome_note = open_result.has_live_remainder
                               ? "sync_partial_fill_live_remainder" : "sync_fill_confirmed";
      string sync_evt_error;
      if(!EEJ_AppendEvent(sync_evt, sync_evt_error))
         PrintFormat("ThembaEA: CRITICAL -- failed to append execution-event journal row for "
                     "position_id=%I64u (%s).", open_result.position_id, sync_evt_error);

      // **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding
      // 13): captures THIS position's own confirmed intraday_mode at the
      // exact moment it was opened, persisted via PositionStateTracker.mqh
      // -- ManageOpenPositions' own exit wrapper now reads this per-
      // position value instead of applying one CURRENT, global
      // InpTimeStopUsesScalpMode input to every position's time-stop for
      // its whole lifetime (mode can and does change between bars after a
      // position opens). decision.intraday_mode is already the real,
      // confirmed value EvaluateAndJournal computed for this exact bar.**
      SPositionExitState entry_state = PST_Load(open_result.position_id);
      entry_state.entry_mode_captured = true;
      entry_state.entry_was_scalp_mode = (decision.intraday_mode == "SCALP");
      if(!PST_Save(open_result.position_id, entry_state))
         PrintFormat("ThembaEA: failed to persist entry-time intraday_mode for "
                     "position_id=%I64u -- its own time-stop will fall back to the global "
                     "InpTimeStopUsesScalpMode input instead.", open_result.position_id);
     }

   // Success — reflect the ACTUAL submitted stop back into the journal
   // record (a floor widening in step 4 may have moved it from the
   // strategy's originally proposed stop).
   decision.stop = final_stop;
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding 11):
   // decision.entry previously stayed at the strategy's originally PROPOSED
   // entry price (set back at candidate-resolution time) even once a real
   // synchronous fill's actual price is known -- so entry, the stop
   // DISTANCE derived from it, and any downstream analysis reading this
   // journal row all described a hypothetical order, not the real fill.
   // Only overwritten for a resolved synchronous fill (open_result.
   // fill_price > 0.0, i.e. DONE/DONE_PARTIAL) -- a PLACED order has no
   // real fill price yet, so the proposed entry remains the best available
   // value until OnTradeTransaction's own async resolution (see that
   // handler's own comment for the current, honest limitation on updating
   // this same field for an async fill).**
   if(open_result.fill_price > 0.0)
     {
      decision.entry = open_result.fill_price;
      decision.has_entry = true;
     }
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 8):
   // risk_percent now scales with the ACTUAL filled volume, not the
   // originally requested sizing.volume -- for an ordinary full DONE fill
   // these are equal (no behavior change), but for a TRADE_RETCODE_DONE_
   // PARTIAL fill only part of the requested volume is genuinely at risk,
   // and journaling the pre-fill sized risk would overstate real exposure.
   // risk_cash scales linearly with volume, so this is a straight ratio of
   // OrderManager's own already-resolved filled_volume to the requested one.
   double actual_risk_cash = sizing.risk_cash_actual;
   if(sizing.volume > 0.0)
      actual_risk_cash = sizing.risk_cash_actual * (open_result.filled_volume / sizing.volume);
   decision.risk_percent = 100.0 * actual_risk_cash / equity;
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
   // the OPENING deal_id IS now recorded, but in the separate execution-
   // event journal below (ExecutionEventJournal.mqh, Codex review finding,
   // ninth round, P1 finding 9's own "proper event schema"), not here.**
   if(open_result.position_id != 0)
      decision.order_id = IntegerToString((long)open_result.position_id);

   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 8):
   // logs/journals the ACTUAL filled volume (open_result.filled_volume),
   // not the originally requested sizing.volume -- for a normal DONE fill
   // these match; for a DONE_PARTIAL fill this reports what genuinely
   // exists at the broker, with an explicit "order_partial_fill" reason tag
   // so the journal itself records that less than the requested volume
   // filled, rather than silently reporting the requested figure as if it
   // were the real outcome.**
   if(open_result.retcode == TRADE_RETCODE_DONE_PARTIAL)
      AppendReason(passed, StringFormat(
         "order_partial_fill_volume_%.2f_of_requested_%.2f", open_result.filled_volume,
         sizing.volume)); // this order is NOT a rejection (opened==true, real exposure
                           // exists) -- appended to 'passed', never 'rejected', which stays
                           // reserved for reasons that actually blocked submission.
   AppendReason(passed, StringFormat(
      "order_submitted_ticket_%I64u_position_id_%I64u_volume_%.2f_fill_%.5f",
      open_result.position_ticket, open_result.position_id, open_result.filled_volume,
      open_result.fill_price));
   PrintFormat("ThembaEA: *** ORDER SUBMITTED *** %s %s volume=%.2f (requested %.2f) ticket=%I64u "
               "position_id=%I64u fill=%.5f stop=%.5f risk_pct=%.4f%s", decision.direction,
               g_symbol, open_result.filled_volume, sizing.volume, open_result.position_ticket,
               open_result.position_id, open_result.fill_price, final_stop, decision.risk_percent,
               (open_result.retcode == TRADE_RETCODE_DONE_PARTIAL) ? " *** PARTIAL FILL ***" : "");

   decision.reasons_passed_json = BuildJsonStringArray(passed);
   decision.reasons_rejected_json = BuildJsonStringArray(rejected);

   // TASK-036 Specification item 4: an accepted-but-not-yet-resolved
   // position (retcode PLACED, position_id still 0) cannot be journaled
   // with a real order_id/deal_id yet -- register it for later
   // correlation so OnTradeTransaction can resolve it once the async fill
   // (or cancellation/expiry) actually arrives.
   //
   // **Corrected, 2026-07-27 (Codex review finding, ninth round, P1 finding
   // 9): this comment previously (and, at the time, correctly) stated that
   // no later journal write explained this record's null order_id/deal_id
   // -- LogAsyncFillResolution logged the resolution via Print only. It now
   // ALSO appends a schema-correct SExecutionEvent row (ExecutionEventJournal.mqh)
   // once OnTradeTransaction resolves this pending order, keyed by
   // decision.signal_id/the durable intent_id/the eventual order_id/deal_id
   // -- this STradeDecision row's own order_id/deal_id remain null (by
   // design, per DecisionJournal.mqh's own append-only contract), but real
   // machine-readable evidence of the eventual fill/cancellation now exists
   // in that separate journal.**
   // **Fixed, 2026-07-28 (Codex review finding, tenth round, P0 finding 2):**
   // this genuinely-async path never released its own reservation anywhere
   // within THIS function call (unlike every other branch above) -- it must
   // be carried through to OnTradeTransaction's own later resolution
   // handlers so THAT code can release the exact reservation this specific
   // submission made, once its own terminal outcome is known.
   // **Fixed, 2026-07-28 (Codex review finding, tenth round, P1 finding 8):**
   // this genuinely-async path had no position_id yet to capture entry-time
   // intraday_mode against (unlike the synchronous branch above, which
   // captures it immediately via PST_Save) -- carrying decision.intraday_mode
   // through AsyncFillCorrelator.mqh lets OnTradeTransaction's own
   // DEAL_ENTRY_IN handler capture it once the position_id is finally known.
   if(open_result.position_id == 0 && open_result.order_ticket != 0)
      AFC_AddPending(open_result.order_ticket, decision.signal_id, reservation_key,
                      decision.intraday_mode == "SCALP");
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

      // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
      // 13): uses THIS position's own persisted entry-time intraday_mode
      // (captured once, in AttemptOrderSubmission, at the moment it was
      // opened) instead of applying one CURRENT, global
      // InpTimeStopUsesScalpMode input uniformly to every position for its
      // whole lifetime. Falls back to the global input only when no
      // entry-time capture exists for this position (e.g. one opened
      // before this fix shipped, or by a mechanism outside
      // AttemptOrderSubmission), matching the input's own original
      // "operator sets this once per deployment" stand-in role.**
      bool uses_scalp_mode = state.entry_mode_captured ? state.entry_was_scalp_mode
                                                          : InpTimeStopUsesScalpMode;

      SExitDecision decision = EO_EvaluatePosition(
         is_long, entry_price, state.initial_stop_price, current_stop, current_price, target_price,
         atr_current, highs, lows, InpSwingDepth, InpMaxLookback, is_new_completed_bar,
         uses_scalp_mode, session_remaining_ratio, session_ratio_known, elapsed_minutes,
         cfg, state);

      // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding
      // 6): PST_Save's own write success is now checked -- a lost write here
      // means this position's own trailing/break-even/profit-lock history
      // reverts to defaults on the next read, which could re-arm an
      // already-armed mechanism; logging it is the practical remediation
      // (this is exit-quality state, not a risk-cap gate, so it does not
      // warrant blocking position management the way a lost intent/risk
      // write would).**
      if(!PST_Save(position_id, state))
         PrintFormat("ThembaEA: PositionStateTracker failed to persist exit state for "
                     "position_id=%I64u -- its trailing/break-even/profit-lock history may "
                     "revert to defaults on the next read.", position_id);

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

   string signal_id = BuildSignalId(g_symbol, InpMagicNumber);

   STradeDecision decision = DJ_NewDecision();
   decision.signal_id = signal_id;
   decision.timestamp = DJ_ServerTimeToUtc(TimeCurrent());
   decision.symbol = g_symbol;
   decision.market_family = IMR_MarketFamilyToString(g_market_family);
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 12): intraday_mode was previously fabricated as SCALP ("unknown --
   // conservative default") and news_state as CLEAR ("unknown -- not
   // evaluated this bar") -- neither was actually true; mode/news were
   // never evaluated this bar at all (that is the entire reason this
   // failure path exists). A downstream analysis grouping by either field
   // would silently attribute a data-failure bar to a real mode/news
   // state it never had, contaminating both. Both now emit their own
   // schema's real "not evaluated" vocabulary (IMR_IntradayModeToString's
   // own NONE for a gating/undefined mode, and "UNKNOWN" for news, added
   // to TRADE_DECISION_SCHEMA.json/schema.py's own Literal alongside this
   // fix) instead of fabricating a plausible-looking value.**
   decision.intraday_mode = IMR_IntradayModeToString(INTRADAY_MODE_NONE);
   decision.regime = EnumToString(REGIME_TRANSITION_OR_UNCERTAIN);
   decision.regime_confidence = 0.0;
   decision.direction = "NONE";
   decision.strategy = "NoTrade";
   decision.setup = "data_failure";
   decision.news_state = "UNKNOWN";
   decision.session_state = "SESSION_TIME_REMAINING_UNKNOWN";
   decision.ea_version = THEMBA_EA_VERSION_STRING;
   decision.git_commit = THEMBA_EA_GIT_COMMIT;

   string reason_arr[];
   AppendReason(reason_arr, failure_reason);
   decision.reasons_rejected_json = BuildJsonStringArray(reason_arr);

   string journal_error;
   if(!DJ_AppendDecision(decision, journal_error))
      PrintFormat("ThembaEA: failed to journal a data-failure decision: %s", journal_error);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex review finding, tenth round, P0 finding 7):  |
//| establishes/refreshes g_daily_weekly_risk_state_valid from the three       |
//| persisted writes DWL_ApplyCashFlowAdjustments/DWL_EnsureDailyBaseline/           |
//| DWL_EnsureWeeklyBaseline actually require, in the mandated order (cash-              |
//| flow adjustment BEFORE either baseline -- see DWL_ApplyCashFlowAdjustments'              |
//| own header for why the order matters). Factored out of EvaluateAndJournal                    |
//| (which still calls this once per completed bar) so OnInit can ALSO call                          |
//| this immediately at restart, BEFORE any deal/tick can be processed --                                |
//| closing the review's own "validity flag starts false at line 229 and is                                  |
//| only initialized through the completed-bar evaluation path... a deal                                        |
//| arriving before that first evaluation can skip the account-wide check"                                          |
//| finding.**                                                                                                          |
//+------------------------------------------------------------------+
void EstablishDailyWeeklyRiskState()
  {
   bool cash_flow_ok       = DWL_ApplyCashFlowAdjustments();
   bool daily_baseline_ok  = DWL_EnsureDailyBaseline();
   bool weekly_baseline_ok = DWL_EnsureWeeklyBaseline();
   g_daily_weekly_risk_state_valid = cash_flow_ok && daily_baseline_ok && weekly_baseline_ok;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex review findings, tenth round, P0 findings 6  |
//| and 7):** ground-truth re-evaluation of every mandatory closure           |
//| condition (daily/weekly loss cap, post-fill total-open-risk cap),            |
//| independent of any persisted "pending" flag surviving a crash. Call from        |
//| OnInit (restart), OnTick, and OnTimer (tick-starved fallback) -- makes             |
//| the closure obligation SELF-HEALING (rediscoverable every tick/timer/                  |
//| restart from ground truth: current daily/weekly baselines and current                     |
//| live positions/orders) rather than dependent on a single persisted flag                       |
//| write having succeeded before a crash (finding 6's own "DailyWeeklyBreach-                        |
//| Manager explicitly admits its fallback does not survive restart" gap). An                             |
//| UNREADABLE daily/weekly state (g_daily_weekly_risk_state_valid == false)                                   |
//| is now itself treated as a reason to attempt closure of EXISTING exposure                                     |
//| -- previously an unreadable state only blocked NEW entries                                                        |
//| (AttemptOrderSubmission's own gate 2), with no obligation at all to                                                   |
//| re-test or close exposure that already existed (finding 7's own required                                                 |
//| correction: "unknown daily/weekly state must block entries AND create a                                                      |
//| durable, repeatedly evaluated fail-closed obligation for existing                                                                exposure").
//+------------------------------------------------------------------+
void ReEvaluateMandatoryClosureObligations()
  {
   if(DWB_IsClosurePending(g_symbol, InpMagicNumber))
     {
      string retry_reasons[];
      DWB_AttemptClosure(g_symbol, InpMagicNumber, retry_reasons);
      return; // already retrying an armed closure -- ground truth already drove this
     }

   bool should_close = false;
   string close_trigger = "";

   if(!g_daily_weekly_risk_state_valid)
     {
      should_close = true;
      close_trigger = "daily_weekly_risk_state_unreadable";
     }
   else
     {
      double daily_change, weekly_change;
      bool daily_breached  = DWL_IsDailyLossBreached(InpDailyLossCapPercent, daily_change);
      bool weekly_breached = DWL_IsWeeklyLossBreached(InpWeeklyLossCapPercent, weekly_change);
      if(daily_breached || weekly_breached)
        {
         should_close = true;
         close_trigger = StringFormat("daily_weekly_reevaluated_daily=%s_weekly=%s",
                                       daily_breached ? "true" : "false",
                                       weekly_breached ? "true" : "false");
        }
     }

   if(!should_close)
     {
      double total_risk_cash;
      bool   total_readable;
      ComputeOwnMagicOpenRiskCash(total_risk_cash, total_readable);
      double equity_now = AccountInfoDouble(ACCOUNT_EQUITY);
      bool total_breached = !total_readable ||
                             (equity_now > 0.0 &&
                              100.0 * total_risk_cash / equity_now > InpRiskCapPercent + 1e-6);
      if(total_breached)
        {
         should_close = true;
         close_trigger = StringFormat("total_open_risk_reevaluated_readable=%s",
                                       total_readable ? "true" : "false");
        }
     }

   if(should_close)
     {
      string reasons[];
      bool closed = DWB_AttemptClosure(g_symbol, InpMagicNumber, reasons);
      PrintFormat("ThembaEA: ground-truth re-evaluation armed a mandatory closure obligation for "
                  "'%s' magic %I64d (trigger=%s) -- closure %s.", g_symbol, InpMagicNumber,
                  close_trigger, closed ? "completed" : "pending (will retry every tick/timer)");
     }
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
   //
   // **Reordered, 2026-07-22 (Codex review finding, seventh round, P1
   // finding 14): DWL_ApplyCashFlowAdjustments() MUST run BEFORE either
   // DWL_Ensure*Baseline() call, never after (see
   // DWL_ApplyCashFlowAdjustments' own header for why the previous order
   // double-counted a fresh baseline's own already-reflected cash flows).**
   //
   // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding 4):
   // g_daily_weekly_risk_state_valid now captures whether EVERY one of these
   // three persisted writes actually succeeded this bar -- previously their
   // return values were discarded, so a lock-timeout write failure silently
   // left a stale/absent baseline in place while AttemptOrderSubmission's own
   // gate 2 (DWL_IsDailyLossBreached/DWL_IsWeeklyLossBreached) treated "no
   // baseline" identically to "not breached", converting a genuine risk-state
   // failure into permission to trade. Threaded into AttemptOrderSubmission
   // below, which now fails closed (rejects new entries) whenever this is
   // false, per that gate's own updated header.
   // EPM_UpdateDailyPeak/EPM_UpdateAccountPeak moved OUT of this
   // once-per-completed-bar function to OnTick's own per-tick path (see
   // OnTick) -- section 8 requires peak tracking on every tick, not once per
   // completed bar.**
   EstablishDailyWeeklyRiskState();

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
   // **Added, 2026-07-27 (Codex review finding, ninth round, P1 finding 11):
   // bar_times[] threads each bar's own TIME alongside the existing shared
   // OHLC/ATR arrays -- ChartPatternStrategy.mqh's new lifecycle registry
   // needs a stable pattern identity across bars (a bar's own TIME never
   // changes; its INDEX into this array shifts by one every new bar), which
   // requires the underlying bar times to be available at this shared
   // evaluation layer, not just derivable prices.
   datetime bar_times[];
   ArrayResize(opens, InpSharedWindowBars);
   ArrayResize(highs, InpSharedWindowBars);
   ArrayResize(lows, InpSharedWindowBars);
   ArrayResize(closes, InpSharedWindowBars);
   ArrayResize(atr_values, InpSharedWindowBars);
   ArrayResize(bar_times, InpSharedWindowBars);
   for(int i = 0; i < InpSharedWindowBars; i++)
     {
      if(!g_md.GetOpen(i, opens[i]) || !g_md.GetHigh(i, highs[i]) || !g_md.GetLow(i, lows[i]) ||
         !g_md.GetClose(i, closes[i]) || !g_md.GetATR(i, atr_values[i], 14) ||
         !g_md.GetTime(i, bar_times[i]))
        {
         Print("ThembaEA: a required price/ATR/time read failed — skipping this bar's evaluation.");
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
   // TASK-002_PHASE2_SPECIFICATION.md section 6 defaults (InpRetestFailureATR
   // 0.2, InpRetestMaxBars 10) -- Codex round-9 P1 finding 11.
   cpCfg.retest_failure_atr = 0.2; cpCfg.retest_max_bars = 10;
   // Codex round-10 P1 finding 9: wires the real InpPatternMaxAgeBars input.
   cpCfg.max_age_bars = InpPatternMaxAgeBars;
   SChartPatternStrategySignal cpSig;
   CPS_EvaluateArray(opens, highs, lows, closes, atr_values, bar_times, g_symbol, InpMagicNumber,
                      effective_regime, structure, cpCfg, cpSig);
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

   string signal_id = BuildSignalId(g_symbol, InpMagicNumber);

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
   decision.ea_version = THEMBA_EA_VERSION_STRING;
   decision.git_commit = THEMBA_EA_GIT_COMMIT;

   // **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 6): TASK-002 section 1's stage-4 post-hoc mode-consistency check --
   // this is what makes intraday_mode actually ROUTE a trading decision,
   // not stay purely journal-only. A candidate whose own expected R is
   // incompatible with the confirmed mode (or whose mode is NONE --
   // gating override or undefined mode_score) is rejected outright, the
   // bar resolving to no-trade exactly like "no eligible candidate."**
   //
   // **Stated, honest deviation (Codex review finding, eighth round, P1
   // finding 12): TASK-002_PHASE2_SPECIFICATION.md's approved pipeline is
   // regime -> mode -> MODE-AWARE strategy generation (each family/mode
   // pair using its own context/entry-timeframe table, a scalp-attempt/
   // unchanged-level counter, and hysteresis confirmed across two closed
   // M1 bars specifically) -> post-hoc consistency, as a final check only.
   // This EA evaluates all five strategies against one shared M15 window,
   // resolves the winner via StrategyRouter/ConflictResolver, and computes
   // mode SEPARATELY -- mode then only VETOES the already-resolved winner
   // by expected R here, exactly as IntradayModeRouter.mqh's own header
   // already states for the hysteresis-cadence half of this same
   // deviation. Reordering to genuine pre-strategy mode-aware generation
   // (per-family/mode context tables, the scalp-attempt counter, a real
   // M1-tick-independent hysteresis hook, and bounded bar cadence
   // configurability instead of hard-coded formula weights) is a
   // substantial, separate architectural task -- not attempted here under
   // review-remediation time pressure, matching this project's own
   // explicit precedent of stating a genuine deferral rather than
   // silently reimplementing it as a smaller, misleadingly-labeled patch.
   // The post-hoc veto below is real and does route decisions (it is not
   // journal-only), it is simply not the approved STAGE ordering yet.**
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
