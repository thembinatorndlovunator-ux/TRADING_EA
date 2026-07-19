//+------------------------------------------------------------------+
//| NdlovuSMC V8.11 - Ultimate SMC + SR Bounce Scalper               |
//|                                                                  |
//| Timeframe hierarchy (as specified):                              |
//|   H1  - overall bias: trend and major structure                  |
//|   M30 - immediate direction: the most recent BOS / CHoCH         |
//|   M15 - working chart: range high/low (clustered SR),            |
//|         consolidation, equilibrium, premium/discount, major OBs  |
//|   M5  - order-block refinement and fair value gaps               |
//|   M1  - entry trigger: liquidity sweep + CHoCH/BOS + candle      |
//|                                                                  |
//| Visuals match the reference chart: BOS/CHoCH marks, EQL/EQH,     |
//| labeled Bullish/Bearish OB zones, Equilibrium and Discount/      |
//| Premium bands, Weak/Strong Low and High on the range boundaries. |
//|                                                                  |
//| Trendlines are deliberately absent: the SMC document itself      |
//| rates diagonal lines as edgeless, so this build trades only      |
//| liquidity, structure, and PD arrays. No journal files. No        |
//| pending orders. Basket entries (2-4 legs), laddered exits,       |
//| break-even on first bank, giveback guard, 45-minute hard exit.   |
//|                                                                  |
//| V8.10 - ASQ Safe Scalping integration:                           |
//|   momentum ENGINE (EMA trend + ATR strength + RSI window +       |
//|   candle momentum) grades every SMC signal with a confluence     |
//|   bonus; a 7-condition MOMENTUM BREAKOUT setup trades expansion  |
//|   beyond value; peak-drawdown lock, baskets-per-day cap,         |
//|   optional session and manual news filters, broker filling-mode |
//|   detection, an R-based runner trail, and a full dashboard.      |
//|                                                                  |
//| V8.11 - breathing room: the stop window moves from 0.35-0.90 to  |
//|   0.60-1.40 M15 ATRs with a 0.35-ATR buffer (floor AND cap move  |
//|   together, the V6.35 lesson), and baskets default to 2 legs so  |
//|   each leg carries 0.5% and targets stay at 1.0R / 1.5R.         |
//+------------------------------------------------------------------+
#property copyright "NdlovuSMC V8.11"
#property version   "8.11"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

enum ENUM_MOM_STRENGTH { MOM_WEAK = 0, MOM_MODERATE = 1, MOM_STRONG = 2 };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "01 - Core"
input long             InpMagicNumber            = 800001;
input bool             InpAllowNewTrades         = true;
input ENUM_TIMEFRAMES  InpBiasTF                 = PERIOD_H1;   // overall bias
input ENUM_TIMEFRAMES  InpDirectionTF            = PERIOD_M30;  // immediate direction (BOS/CHoCH)
input ENUM_TIMEFRAMES  InpWorkingTF              = PERIOD_M15;  // range, PD arrays, major OBs
input ENUM_TIMEFRAMES  InpRefineTF               = PERIOD_M5;   // OB refinement and FVGs
input ENUM_TIMEFRAMES  InpEntryTF                = PERIOD_M1;   // sweep + shift + entry candle
input double           InpMinimumSignalScore     = 74.0;
input int              InpMaxSpreadPoints        = 0;
input int              InpMaxSlippagePoints      = 30;
input bool             InpUseBoomCrashFilter     = true;
input bool             InpVerboseLog             = true;

input group "02 - Risk"
input double           InpRiskPercent            = 1.00;        // TOTAL risk per basket
input double           InpMaxRiskPercent         = 2.00;
input double           InpMaxDrawdownPercent     = 20.0;
input double           InpMaxLotPerLeg           = 5.0;
input double           InpMinLotMaxRiskPercent   = 2.0;
input double           InpDailyLossLimitPercent  = 3.0;
input double           InpDailyProfitTargetPct   = 0.0;
input bool             InpCloseAllAtDailyLock    = true;

input group "03 - Basket (2-4 positions per signal)"
input int              InpLegsStrongSignal       = 2;           // score >= 88 (raise back to 3-4 only after the wider stops prove out)
input int              InpLegsGoodSignal         = 2;           // score >= 80
input int              InpLegsBaseSignal         = 2;
input double           InpTP1R                   = 1.0;
input double           InpTP2R                   = 1.5;
input double           InpTP3R                   = 2.0;
input double           InpTP4R                   = 2.5;
input double           InpBasketBreakEvenAtR     = 1.0;
input double           InpGivebackArmR           = 0.8;
input double           InpGivebackFloorR         = 0.1;
input int              InpMaxHoldMinutes         = 45;
input int              InpCooldownEntryBars      = 3;
input bool             InpExitOnDirectionFlip    = true;        // M30 direction flipping against the basket ends it
input bool             InpUseRunnerTrail         = true;        // after break-even, trail the rest behind the peak R
input double           InpTrailStartR            = 1.5;         // trailing arms once the basket has seen this many R
input double           InpTrailStepR             = 0.6;         // the stop follows this far behind the peak R

input group "04 - Stops"
input double           InpMinStopATR             = 0.60;        // stop floor in working-TF ATRs: room to breathe through M1 noise
input double           InpMaxStopATR             = 1.40;        // cap raised WITH the floor so wider stops are allowed, not rejected
input double           InpStopBufferATR          = 0.35;        // pad beyond the structure, in working-TF ATRs
input int              InpATRPeriod              = 14;

input group "05 - SMC Setups"
input bool             InpUseSweepShift          = true;        // liquidity sweep + M1 CHoCH + entry candle (flagship)
input int              InpSweepLookback          = 30;          // entry-TF bars forming the liquidity pool
input int              InpShiftLookback          = 6;           // micro lower-high/higher-low to break after the sweep
input double           InpSweepScore             = 88.0;
input bool             InpUseSRBounce            = true;        // rejection at the clustered range low/high
input int              InpClusterMinTouches      = 2;
input double           InpClusterTolATR          = 0.30;
input double           InpSRScore                = 82.0;
input bool             InpUseOrderBlocks         = true;        // M15 blocks, boundaries refined on M5
input bool             InpRefineOBOnM5           = true;
input int              InpOBLookbackBars         = 160;
input int              InpOBMaxAgeBars           = 64;
input double           InpOBMinImpulseATR        = 1.0;
input double           InpOBScore                = 84.0;
input double           InpOBConfluenceBonus      = 5.0;
input bool             InpUseFVG                 = true;        // M5 fair value gaps, first return only
input int              InpFVGLookbackBars        = 90;
input int              InpFVGMaxAgeBars          = 36;
input double           InpFVGMinGapATR           = 0.12;
input double           InpFVGScore               = 80.0;
input bool             InpUseBOSRetest           = true;        // M1 break of structure retested
input int              InpBOSLookback            = 8;
input double           InpBOSRetestScore         = 81.0;

input group "06 - Analysis"
input int              InpSwingDepth             = 2;
input int              InpBiasLookbackBars       = 140;         // bias-TF bars
input int              InpDirectionLookbackBars  = 120;         // direction-TF bars
input int              InpLevelLookbackBars      = 220;         // working-TF bars
input double           InpEqualTolATR            = 0.10;        // EQL/EQH tolerance in working-TF ATRs
input double           InpPDBandPercent          = 10.0;        // equilibrium band as % of the range
input double           InpExtremeBandPercent     = 15.0;        // premium/discount extreme bands as % of the range
input double           InpExpansionATRFactor     = 1.8;

input group "07 - Visuals"
input bool             InpDrawVisuals            = true;
input bool             InpShowStructureMarks     = true;        // BOS / CHoCH / EQL / EQH
input bool             InpShowZones              = true;        // order blocks and FVGs
input bool             InpShowPDBands            = true;        // equilibrium, premium, discount
input bool             InpShowRangeLines         = true;        // Weak/Strong High and Low
input bool             InpShowDashboard          = true;
input int              InpDashboardX             = 12;
input int              InpDashboardY             = 18;

input group "08 - ASQ Momentum Engine (V8.10)"
input bool             InpUseMomentumEngine      = true;        // EMA trend + strength + RSI window + candle momentum
input ENUM_TIMEFRAMES  InpMomTF                  = PERIOD_M5;   // the engine timeframe
input int              InpMomEmaFast             = 50;
input int              InpMomEmaSlow             = 200;
input ENUM_MOM_STRENGTH InpMomTrendStrength      = MOM_MODERATE; // required EMA separation vs ATR
input int              InpMomRsiPeriod           = 10;
input double           InpMomRsiBuyMin           = 40.0;        // RSI window, not overbought/oversold extremes
input double           InpMomRsiBuyMax           = 65.0;
input double           InpMomRsiSellMin          = 35.0;
input double           InpMomRsiSellMax          = 60.0;
input bool             InpUseMomentumBreakout    = true;        // the ASQ 7-condition breakout as its own setup
input int              InpBreakoutLookback       = 20;          // engine-TF bars whose extreme must break
input double           InpBreakoutBufferATR      = 0.5;         // break allowed this many ATRs early
input double           InpMomBreakoutScore       = 76.0;        // + strength and bias bonuses
input double           InpMomConfluenceBonus     = 3.0;         // SMC signals aligned with the engine are upgraded

input group "09 - Protection (V8.10)"
input double           InpMaxDrawdownLockPct     = 10.0;        // block new baskets above this equity drawdown from peak (0 = off)
input int              InpMaxDayBaskets          = 10;          // baskets per day (0 = unlimited)
input bool             InpUseSessionFilter       = false;       // keep OFF for 24/7 synthetics; useful on gold
input int              InpSessionStartHour       = 8;
input int              InpSessionEndHour         = 20;
input bool             InpAvoidFridayClose       = false;
input int              InpFridayCutoffHour       = 16;
input bool             InpUseNewsFilter          = false;       // manual windows for real markets (server time HH:MM)
input string           InpNewsTime1              = "";
input string           InpNewsTime2              = "";
input string           InpNewsTime3              = "";
input int              InpNewsMinsBefore         = 30;
input int              InpNewsMinsAfter          = 15;

//+------------------------------------------------------------------+
//| Structures and globals                                           |
//+------------------------------------------------------------------+
struct ScalpSignal
{
   bool     valid;
   int      direction;
   double   score;
   string   setup;
   string   reason;
   double   sl;
};

struct LevelZone
{
   bool     valid;
   double   low;
   double   high;
   datetime start;
};

struct StructMark
{
   bool     valid;
   int      kind;        // 1 BOS, 2 CHoCH, 3 EQL, 4 EQH
   int      direction;   // 1 bullish, -1 bearish
   double   level;
   datetime t_from;
   datetime t_to;
};

#define MAX_MARKS 6

datetime g_last_entry_bar = 0;
datetime g_day_start = 0;
double   g_day_start_equity = 0.0;
bool     g_daily_locked = false;
string   g_lock_reason = "";
string   g_last_action = "Warming up";
datetime g_last_basket_close = 0;

// hierarchy state
int      g_bias = 0;              // H1
int      g_dir30 = 0;             // M30 immediate direction
bool     g_expansion = false;
double   g_range_high = 0.0, g_range_low = 0.0;
int      g_high_touches = 0, g_low_touches = 0;
double   g_high_width = 0.0, g_low_width = 0.0;
bool     g_low_swept = false, g_high_swept = false;
double   g_equilibrium = 0.0;
datetime g_range_start = 0;

LevelZone g_ob_bull, g_ob_bear;         // raw M15 blocks
LevelZone g_ob_bull_ref, g_ob_bear_ref; // M5-refined boundaries
LevelZone g_fvg_bull, g_fvg_bear;       // M5 gaps
StructMark g_marks[MAX_MARKS];

// basket state
int      g_basket_dir = 0;
double   g_basket_entry = 0.0;
double   g_basket_risk = 0.0;
datetime g_basket_time = 0;
int      g_basket_legs = 0;
bool     g_basket_be_done = false;
double   g_basket_peak_r = 0.0;

// V8.10 momentum engine (cached per engine-TF bar)
bool     g_mom_bull_ok = false;
bool     g_mom_bear_ok = false;
int      g_mom_strength = -1;      // -1 none, 0 weak, 1 moderate, 2 strong
double   g_mom_rsi = 50.0;
datetime g_last_breakout_fire = 0;

// V8.10 protection
double   g_peak_balance = 0.0;
double   g_peak_dd = 0.0;
double   g_current_dd = 0.0;
int      g_day_baskets = 0;
string   g_gv_peak_dd = "";

//+------------------------------------------------------------------+
//| Lifecycle                                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippagePoints);
   trade.SetMarginMode();

   // V8.10 (from ASQ): match the broker's supported filling mode so
   // orders never bounce on FOK/IOC mismatches.
   long fill_policy = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill_policy & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fill_policy & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // V8.10 (from ASQ): peak-drawdown memory survives restarts.
   g_peak_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_gv_peak_dd = "NSMC_PeakDD_" + _Symbol + "_" + IntegerToString((int)InpMagicNumber);
   if(!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(g_gv_peak_dd))
      g_peak_dd = GlobalVariableGet(g_gv_peak_dd);

   ResetDailyState();
   RefreshHierarchy(true);
   Print("NdlovuSMC V8.11 initialized. Breathing-room stops (0.60-1.40 ATR window), 2-leg baskets at 0.5% per leg.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteByPrefix("NSMC_");
}

void OnTick()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippagePoints);

   ResetDailyStateIfNeeded();
   CheckDailyLimits();
   UpdateDrawdownGuard();
   ManageBasket();
   DrawDashboard();

   if(g_daily_locked || !InpAllowNewTrades)
      return;
   if(!IsNewBar(InpEntryTF, g_last_entry_bar))
      return;

   RefreshHierarchy(false);
   RefreshMomentum();

   if(CountOurPositions() > 0)
      return;
   if(g_last_basket_close > 0 &&
      TimeCurrent() - g_last_basket_close < (long)MathMax(0, InpCooldownEntryBars) * PeriodSeconds(InpEntryTF))
   {
      g_last_action = "Cooldown after the last basket";
      return;
   }
   if(InpMaxDrawdownLockPct > 0.0 && g_current_dd >= InpMaxDrawdownLockPct)
   {
      g_last_action = "Drawdown lock: " + DoubleToString(g_current_dd, 1) + "% from the peak";
      return;
   }
   if(InpMaxDayBaskets > 0 && g_day_baskets >= InpMaxDayBaskets)
   {
      g_last_action = "Daily basket cap reached (" + IntegerToString(g_day_baskets) + ")";
      return;
   }
   if(InpUseSessionFilter && !SessionOK())
   {
      g_last_action = "Outside the trading session";
      return;
   }
   if(InpUseNewsFilter && !NewsOK())
   {
      g_last_action = "Manual news window: standing aside";
      return;
   }
   if(!SpreadOK())
   {
      g_last_action = "Spread above the cap";
      return;
   }
   if(g_expansion)
   {
      g_last_action = "Volatility expansion: standing aside";
      return;
   }

   ScalpSignal best;
   BuildBestSignal(best);
   if(!best.valid || best.score < InpMinimumSignalScore)
      return;
   if(!DirectionAllowed(best.direction))
      return;

   OpenBasket(best);
}

//+------------------------------------------------------------------+
//| Hierarchy refresh: each layer cached on its own timeframe        |
//+------------------------------------------------------------------+
void RefreshHierarchy(bool force)
{
   static datetime b_bias = 0, b_dir = 0, b_work = 0, b_ref = 0;

   datetime t = iTime(_Symbol, InpBiasTF, 0);
   if(force || (t != b_bias && t > 0))
   {
      b_bias = t;
      g_bias = StructureTrend(InpBiasTF, InpBiasLookbackBars);
   }

   t = iTime(_Symbol, InpDirectionTF, 0);
   if(force || (t != b_dir && t > 0))
   {
      b_dir = t;
      RefreshDirectionM30();
   }

   t = iTime(_Symbol, InpWorkingTF, 0);
   if(force || (t != b_work && t > 0))
   {
      b_work = t;
      RefreshWorkingChart();
      RefreshOrderBlocks();
      if(InpDrawVisuals)
         DrawWorkingChart();
   }

   t = iTime(_Symbol, InpRefineTF, 0);
   if(force || (t != b_ref && t > 0))
   {
      b_ref = t;
      RefreshFVGs();
      RefineOrderBlocks();
      if(InpDrawVisuals && InpShowZones)
         DrawZones();
   }
}

int StructureTrend(ENUM_TIMEFRAMES tf, int lookback)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, tf, 0, MathMax(60, lookback + 20), r);
   if(copied < 40)
      return 0;
   int hi_a = -1, hi_b = -1, lo_a = -1, lo_b = -1;
   FindLastTwoSwings(r, copied, InpSwingDepth, -1, hi_a, hi_b);
   FindLastTwoSwings(r, copied, InpSwingDepth, 1, lo_a, lo_b);
   if(hi_a < 0 || hi_b < 0 || lo_a < 0 || lo_b < 0)
      return 0;
   bool hh = r[hi_a].high > r[hi_b].high;
   bool hl = r[lo_a].low > r[lo_b].low;
   bool lh = r[hi_a].high < r[hi_b].high;
   bool ll = r[lo_a].low < r[lo_b].low;
   if(hh && hl) return 1;
   if(lh && ll) return -1;
   return 0;
}

// M30 immediate direction: the most recent break of structure decides.
void RefreshDirectionM30()
{
   g_dir30 = 0;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, InpDirectionTF, 0, MathMax(80, InpDirectionLookbackBars + 20), r);
   if(copied < 40)
      return;

   int trend = StructureTrend(InpDirectionTF, InpDirectionLookbackBars);
   int hi_a = -1, hi_b = -1, lo_a = -1, lo_b = -1;
   FindLastTwoSwings(r, copied, InpSwingDepth, -1, hi_a, hi_b);
   FindLastTwoSwings(r, copied, InpSwingDepth, 1, lo_a, lo_b);

   bool broke_up = hi_a > 0 && r[1].close > r[hi_a].high;
   bool broke_dn = lo_a > 0 && r[1].close < r[lo_a].low;
   if(broke_up && !broke_dn)
      g_dir30 = 1;
   else if(broke_dn && !broke_up)
      g_dir30 = -1;
   else
      g_dir30 = trend;
}

// M15 working chart: clustered range, PD arrays, sweep status, marks.
void RefreshWorkingChart()
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, InpWorkingTF, 0, MathMax(80, InpLevelLookbackBars + 30), r);
   if(copied < 60)
      return;

   double atr = GetATR(InpWorkingTF, 1);
   double atr_avg = GetAverageATR(InpWorkingTF, 60);
   g_expansion = (atr > 0.0 && atr_avg > 0.0 &&
                  atr >= atr_avg * MathMax(1.1, InpExpansionATRFactor));

   FindClusterBoundary(r, copied, -1, g_range_high, g_high_touches, g_high_width);
   FindClusterBoundary(r, copied, 1, g_range_low, g_low_touches, g_low_width);
   g_equilibrium = (g_range_high > 0.0 && g_range_low > 0.0)
                   ? (g_range_high + g_range_low) * 0.5 : 0.0;

   // Range start for drawing: the older of the two boundary origins.
   g_range_start = r[MathMin(copied - 1, InpLevelLookbackBars)].time;

   // Weak vs strong extremes: a boundary is WEAK until its liquidity has
   // been purged (a wick beyond it that closed back inside).
   g_low_swept = false;
   g_high_swept = false;
   if(g_range_low > 0.0 || g_range_high > 0.0)
   {
      int scan = MathMin(copied - 1, 60);
      for(int i = 1; i <= scan; i++)
      {
         if(g_range_low > 0.0 && r[i].low < g_range_low - g_low_width &&
            r[i].close > g_range_low - g_low_width)
            g_low_swept = true;
         if(g_range_high > 0.0 && r[i].high > g_range_high + g_high_width &&
            r[i].close < g_range_high + g_high_width)
            g_high_swept = true;
      }
   }

   BuildStructureMarks(r, copied, atr);
}

// Recent BOS/CHoCH events and equal highs/lows on the working chart.
void BuildStructureMarks(const MqlRates &r[], int copied, double atr)
{
   for(int i = 0; i < MAX_MARKS; i++)
      g_marks[i].valid = false;
   int used = 0;

   // Walk recent history for structure breaks: a close beyond the last
   // confirmed swing. BOS = with the prior leg, CHoCH = against it.
   int depth = MathMax(2, InpSwingDepth);
   int prior_dir = 0;
   for(int i = MathMin(copied - depth - 2, 90); i >= 2 && used < 4; i--)
   {
      // swing high broken upward by bar i-1?
      if(IsSwingHigh(r, copied, i, depth))
      {
         for(int j = i - 1; j >= MathMax(2, i - 12); j--)
         {
            if(r[j].close > r[i].high)
            {
               int kind = (prior_dir <= 0) ? 2 : 1;   // CHoCH if the leg was down
               g_marks[used].valid = true;
               g_marks[used].kind = kind;
               g_marks[used].direction = 1;
               g_marks[used].level = r[i].high;
               g_marks[used].t_from = r[i].time;
               g_marks[used].t_to = r[j].time;
               used++;
               prior_dir = 1;
               break;
            }
            if(r[j].low < r[i].high - atr * 2.0)
               break;
         }
      }
      if(used >= 4)
         break;
      if(IsSwingLow(r, copied, i, depth))
      {
         for(int j = i - 1; j >= MathMax(2, i - 12); j--)
         {
            if(r[j].close < r[i].low)
            {
               int kind = (prior_dir >= 0) ? 2 : 1;
               g_marks[used].valid = true;
               g_marks[used].kind = kind;
               g_marks[used].direction = -1;
               g_marks[used].level = r[i].low;
               g_marks[used].t_from = r[i].time;
               g_marks[used].t_to = r[j].time;
               used++;
               prior_dir = -1;
               break;
            }
            if(r[j].high > r[i].low + atr * 2.0)
               break;
         }
      }
   }

   // Equal lows / highs still holding: resting liquidity worth marking.
   double tol = atr * MathMax(0.03, InpEqualTolATR);
   int lo1 = -1, lo2 = -1, hi1 = -1, hi2 = -1;
   FindLastTwoSwings(r, copied, depth, 1, lo1, lo2);
   FindLastTwoSwings(r, copied, depth, -1, hi1, hi2);
   if(used < MAX_MARKS && lo1 > 0 && lo2 > 0 &&
      MathAbs(r[lo1].low - r[lo2].low) <= tol && r[1].close > r[lo1].low)
   {
      g_marks[used].valid = true;
      g_marks[used].kind = 3;
      g_marks[used].direction = 1;
      g_marks[used].level = MathMin(r[lo1].low, r[lo2].low);
      g_marks[used].t_from = r[lo2].time;
      g_marks[used].t_to = r[lo1].time;
      used++;
   }
   if(used < MAX_MARKS && hi1 > 0 && hi2 > 0 &&
      MathAbs(r[hi1].high - r[hi2].high) <= tol && r[1].close < r[hi1].high)
   {
      g_marks[used].valid = true;
      g_marks[used].kind = 4;
      g_marks[used].direction = -1;
      g_marks[used].level = MathMax(r[hi1].high, r[hi2].high);
      g_marks[used].t_from = r[hi2].time;
      g_marks[used].t_to = r[hi1].time;
   }
}

//+------------------------------------------------------------------+
//| Direction and location gates (the PD-array discipline)           |
//+------------------------------------------------------------------+
bool TradeDirectionOK(int direction)
{
   if(g_bias != 0)
      return direction == g_bias && g_dir30 != -direction;
   // Ranging H1: the M30 direction leads; a flat M30 allows both sides.
   return g_dir30 == 0 || g_dir30 == direction;
}

bool LocationOK(int direction, double price)
{
   if(g_equilibrium <= 0.0)
      return true;
   double band = (g_range_high - g_range_low) * MathMax(1.0, InpPDBandPercent) / 200.0;
   if(direction == 1)
      return price < g_equilibrium + band;   // buys from equilibrium down (discount side)
   return price > g_equilibrium - band;      // sells from equilibrium up (premium side)
}

//+------------------------------------------------------------------+
//| Clustered boundary detection (equal highs / equal lows)           |
//+------------------------------------------------------------------+
bool FindClusterBoundary(const MqlRates &r[], int copied, int direction,
                         double &level, int &touches, double &half_width)
{
   level = 0.0;
   touches = 0;
   half_width = 0.0;
   double atr = GetATR(InpWorkingTF, 1);
   if(atr <= 0.0)
      return false;
   double tol = atr * MathMax(0.05, InpClusterTolATR);
   int depth = MathMax(2, InpSwingDepth);
   int max_i = MathMin(copied - depth - 1, InpLevelLookbackBars);

   double pivots[128];
   int n = 0;
   for(int i = depth + 1; i < max_i && n < 128; i++)
   {
      bool swing = (direction == -1) ? IsSwingHigh(r, copied, i, depth)
                                     : IsSwingLow(r, copied, i, depth);
      if(!swing)
         continue;
      pivots[n] = (direction == -1) ? r[i].high : r[i].low;
      n++;
   }
   if(n < MathMax(2, InpClusterMinTouches))
      return false;

   double best_level = 0.0, best_width = 0.0;
   int best_touches = 0;
   double current = r[1].close;
   for(int a = 0; a < n; a++)
   {
      double sum = 0.0, lo = pivots[a], hi = pivots[a];
      int c = 0;
      for(int b = 0; b < n; b++)
      {
         if(MathAbs(pivots[b] - pivots[a]) > tol)
            continue;
         sum += pivots[b];
         c++;
         lo = MathMin(lo, pivots[b]);
         hi = MathMax(hi, pivots[b]);
      }
      if(c == 0)
         continue;
      double mean = sum / c;
      bool better = c > best_touches ||
                    (c == best_touches && MathAbs(mean - current) < MathAbs(best_level - current));
      if(better)
      {
         best_touches = c;
         best_level = mean;
         best_width = (hi - lo) * 0.5;
      }
   }
   if(best_touches < MathMax(2, InpClusterMinTouches))
      return false;

   // A boundary closed through twice in a row is retired.
   int consecutive = 0;
   for(int i = 1; i <= MathMin(copied - 1, InpLevelLookbackBars); i++)
   {
      bool beyond = (direction == 1) ? r[i].close < best_level : r[i].close > best_level;
      if(beyond)
      {
         consecutive++;
         if(consecutive >= 2)
            return false;
      }
      else
         break;
   }

   level = NormalizePrice(best_level);
   touches = best_touches;
   half_width = MathMax(best_width, tol * 0.5);
   return true;
}

//+------------------------------------------------------------------+
//| Order blocks: M15 raw block, M5-refined boundaries               |
//+------------------------------------------------------------------+
void RefreshOrderBlocks()
{
   if(!InpUseOrderBlocks)
   {
      g_ob_bull.valid = false;
      g_ob_bear.valid = false;
      g_ob_bull_ref.valid = false;
      g_ob_bear_ref.valid = false;
      return;
   }
   ScanOB(1, g_ob_bull);
   ScanOB(-1, g_ob_bear);
}

bool ScanOB(int direction, LevelZone &z)
{
   z.valid = false;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, InpWorkingTF, 0, MathMax(60, InpOBLookbackBars + 15), r);
   if(copied < 40)
      return false;
   double atr = GetATR(InpWorkingTF, 1);
   if(atr <= 0.0)
      return false;
   double min_imp = atr * MathMax(0.25, InpOBMinImpulseATR);
   int limit = MathMin(copied - 8, MathMin(InpOBLookbackBars, MathMax(10, InpOBMaxAgeBars)));

   for(int i = 2; i <= limit; i++)
   {
      if(direction == 1)
      {
         if(r[i].close >= r[i].open) continue;               // last DOWNCLOSE candle
         if(r[i - 1].close <= r[i].high) continue;           // displacement closes above it
         double impulse_high = r[i - 1].high;
         for(int k = i - 1; k >= MathMax(1, i - 6); k--)
            impulse_high = MathMax(impulse_high, r[k].high);
         if(impulse_high - r[i].low < min_imp) continue;
         bool mitigated = false;
         for(int m = i - 2; m >= 3; m--)
            if(r[m].low <= r[i].high) { mitigated = true; break; }
         if(mitigated) continue;
         z.valid = true; z.low = r[i].low; z.high = r[i].high; z.start = r[i].time;
         return true;
      }
      else
      {
         if(r[i].close <= r[i].open) continue;
         if(r[i - 1].close >= r[i].low) continue;
         double impulse_low = r[i - 1].low;
         for(int k = i - 1; k >= MathMax(1, i - 6); k--)
            impulse_low = MathMin(impulse_low, r[k].low);
         if(r[i].high - impulse_low < min_imp) continue;
         bool mitigated2 = false;
         for(int m = i - 2; m >= 3; m--)
            if(r[m].high >= r[i].low) { mitigated2 = true; break; }
         if(mitigated2) continue;
         z.valid = true; z.low = r[i].low; z.high = r[i].high; z.start = r[i].time;
         return true;
      }
   }
   return false;
}

// M5 refinement: the precise opposing candle INSIDE the M15 block window.
void RefineOrderBlocks()
{
   g_ob_bull_ref.valid = false;
   g_ob_bear_ref.valid = false;
   if(!InpUseOrderBlocks || !InpRefineOBOnM5)
      return;
   if(g_ob_bull.valid)
      RefineOne(1, g_ob_bull, g_ob_bull_ref);
   if(g_ob_bear.valid)
      RefineOne(-1, g_ob_bear, g_ob_bear_ref);
}

void RefineOne(int direction, const LevelZone &raw, LevelZone &refined)
{
   refined.valid = false;
   datetime from = raw.start;
   datetime to = raw.start + (datetime)PeriodSeconds(InpWorkingTF);

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, InpRefineTF, from - (datetime)PeriodSeconds(InpRefineTF),
                          to + (datetime)(2 * PeriodSeconds(InpRefineTF)), r);
   if(copied < 4)
      return;

   // Newest-first: find the LAST opposing refine-TF candle inside the window
   // whose next candle closes beyond it (a mini displacement).
   for(int i = 1; i < copied - 1; i++)
   {
      if(r[i].time < from || r[i].time >= to)
         continue;
      if(direction == 1)
      {
         if(r[i].close >= r[i].open) continue;
         if(i - 1 >= 0 && r[i - 1].close > r[i].high)
         {
            refined.valid = true;
            refined.low = r[i].low;
            refined.high = r[i].high;
            refined.start = r[i].time;
            return;
         }
      }
      else
      {
         if(r[i].close <= r[i].open) continue;
         if(i - 1 >= 0 && r[i - 1].close < r[i].low)
         {
            refined.valid = true;
            refined.low = r[i].low;
            refined.high = r[i].high;
            refined.start = r[i].time;
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| M5 fair value gaps: fresh, untouched, first return only          |
//+------------------------------------------------------------------+
void RefreshFVGs()
{
   if(!InpUseFVG)
   {
      g_fvg_bull.valid = false;
      g_fvg_bear.valid = false;
      return;
   }
   ScanFVG(1, g_fvg_bull);
   ScanFVG(-1, g_fvg_bear);
}

bool ScanFVG(int direction, LevelZone &z)
{
   z.valid = false;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, InpRefineTF, 0, MathMax(50, InpFVGLookbackBars + 10), r);
   if(copied < 20)
      return false;
   double atr = GetATR(InpRefineTF, 1);
   if(atr <= 0.0)
      return false;
   double min_gap = MathMax(3.0 * _Point, atr * MathMax(0.03, InpFVGMinGapATR));
   int limit = MathMin(copied - 3, MathMin(InpFVGLookbackBars, MathMax(6, InpFVGMaxAgeBars)));

   for(int i = 2; i <= limit; i++)
   {
      if(direction == 1)
      {
         double lo = r[i + 2].high, hi = r[i].low;
         if(hi - lo < min_gap) continue;
         if(r[i + 1].close <= r[i + 1].open || BodyRatio(r[i + 1]) < 0.55) continue;
         bool touched = false;
         for(int m = i - 1; m >= 2; m--)
            if(r[m].low <= hi) { touched = true; break; }
         if(touched) continue;
         z.valid = true; z.low = lo; z.high = hi; z.start = r[i + 2].time;
         return true;
      }
      else
      {
         double lo2 = r[i].high, hi2 = r[i + 2].low;
         if(hi2 - lo2 < min_gap) continue;
         if(r[i + 1].close >= r[i + 1].open || BodyRatio(r[i + 1]) < 0.55) continue;
         bool touched2 = false;
         for(int m = i - 1; m >= 2; m--)
            if(r[m].high >= lo2) { touched2 = true; break; }
         if(touched2) continue;
         z.valid = true; z.low = lo2; z.high = hi2; z.start = r[i + 2].time;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Entry setups                                                     |
//+------------------------------------------------------------------+
void BuildBestSignal(ScalpSignal &best)
{
   EmptySignal(best);

   MqlRates e[];
   ArraySetAsSeries(e, true);
   int need = MathMax(40, InpSweepLookback + InpShiftLookback + 10);
   int copied = CopyRates(_Symbol, InpEntryTF, 0, need, e);
   if(copied < 25)
      return;

   double atr15 = GetATR(InpWorkingTF, 1);
   if(atr15 <= 0.0)
      return;

   ScalpSignal s;
   if(InpUseSweepShift)
   {
      BuildSweepShift(e, copied, atr15, 1, s);
      KeepBetter(best, s);
      BuildSweepShift(e, copied, atr15, -1, s);
      KeepBetter(best, s);
   }
   if(InpUseSRBounce)
   {
      BuildSRBounce(e, copied, atr15, 1, s);
      KeepBetter(best, s);
      BuildSRBounce(e, copied, atr15, -1, s);
      KeepBetter(best, s);
   }
   if(InpUseOrderBlocks)
   {
      BuildOBScalp(e, copied, 1, s);
      KeepBetter(best, s);
      BuildOBScalp(e, copied, -1, s);
      KeepBetter(best, s);
   }
   if(InpUseFVG)
   {
      BuildFVGScalp(e, copied, 1, s);
      KeepBetter(best, s);
      BuildFVGScalp(e, copied, -1, s);
      KeepBetter(best, s);
   }
   if(InpUseBOSRetest)
   {
      BuildBOSRetest(e, copied, atr15, s);
      KeepBetter(best, s);
   }

   if(InpUseMomentumEngine && InpUseMomentumBreakout)
   {
      BuildMomentumBreakout(s);
      KeepBetter(best, s);
   }

   // Any winning signal firing INSIDE an aligned order block is upgraded.
   if(best.valid && InpUseOrderBlocks && InpOBConfluenceBonus > 0.0 &&
      StringFind(best.setup, "OBScalp") < 0)
   {
      LevelZone z = ActiveOB(best.direction);
      if(z.valid && e[1].low <= z.high && e[1].high >= z.low)
      {
         best.score = MathMin(100.0, best.score + InpOBConfluenceBonus);
         best.reason = best.reason + " + order block confluence";
      }
   }

   // V8.10: SMC location + ASQ momentum agreeing is the highest grade -
   // any surviving signal aligned with the engine earns the bonus.
   if(best.valid && InpUseMomentumEngine && InpMomConfluenceBonus > 0.0 &&
      StringFind(best.setup, "MomBreakout") < 0)
   {
      bool aligned = (best.direction == 1 && g_mom_bull_ok) ||
                     (best.direction == -1 && g_mom_bear_ok);
      if(aligned)
      {
         best.score = MathMin(100.0, best.score + InpMomConfluenceBonus);
         best.reason = best.reason + " + momentum aligned";
      }
   }
}

LevelZone ActiveOB(int direction)
{
   LevelZone z;
   z.valid = false;
   z.low = 0.0;
   z.high = 0.0;
   z.start = 0;
   if(direction == 1)
   {
      if(g_ob_bull_ref.valid) return g_ob_bull_ref;
      return g_ob_bull;
   }
   if(g_ob_bear_ref.valid) return g_ob_bear_ref;
   return g_ob_bear;
}

bool InsideZone(const LevelZone &z, double price)
{
   return z.valid && price >= z.low && price <= z.high;
}

// Flagship: liquidity sweep -> M1 structure shift -> entry candle,
// taken only at a meaningful location (range low/high, OB, or FVG).
void BuildSweepShift(const MqlRates &e[], int copied, double atr15, int direction, ScalpSignal &s)
{
   EmptySignal(s);
   if(!TradeDirectionOK(direction))
      return;
   double close1 = e[1].close;
   if(!LocationOK(direction, close1))
      return;

   // Location: near the range boundary or inside an aligned OB/FVG.
   bool at_location = false;
   string where = "";
   if(direction == 1)
   {
      if(g_range_low > 0.0 && MathAbs(e[1].low - g_range_low) <= atr15 * 0.50)
      { at_location = true; where = "range low"; }
      LevelZone ob = ActiveOB(1);
      if(!at_location && InsideZone(ob, e[1].low))
      { at_location = true; where = "bullish order block"; }
      if(!at_location && InsideZone(g_fvg_bull, e[1].low))
      { at_location = true; where = "bullish FVG"; }
   }
   else
   {
      if(g_range_high > 0.0 && MathAbs(e[1].high - g_range_high) <= atr15 * 0.50)
      { at_location = true; where = "range high"; }
      LevelZone ob = ActiveOB(-1);
      if(!at_location && InsideZone(ob, e[1].high))
      { at_location = true; where = "bearish order block"; }
      if(!at_location && InsideZone(g_fvg_bear, e[1].high))
      { at_location = true; where = "bearish FVG"; }
   }
   if(!at_location)
      return;

   // The liquidity pool: the extreme of the bars BEFORE the sweep window.
   int pool_from = 4;
   int pool_to = MathMin(copied - 2, pool_from + MathMax(10, InpSweepLookback));
   double pool = (direction == 1) ? e[pool_from].low : e[pool_from].high;
   for(int i = pool_from; i <= pool_to; i++)
      pool = (direction == 1) ? MathMin(pool, e[i].low) : MathMax(pool, e[i].high);

   // The sweep: one of the last 3 closed bars wicks beyond the pool and
   // closes back on the right side of it.
   bool swept = false;
   double sweep_extreme = 0.0;
   for(int j = 1; j <= 3; j++)
   {
      if(direction == 1 && e[j].low < pool && e[j].close > pool)
      {
         swept = true;
         sweep_extreme = (sweep_extreme == 0.0) ? e[j].low : MathMin(sweep_extreme, e[j].low);
      }
      if(direction == -1 && e[j].high > pool && e[j].close < pool)
      {
         swept = true;
         sweep_extreme = (sweep_extreme == 0.0) ? e[j].high : MathMax(sweep_extreme, e[j].high);
      }
   }
   if(!swept)
      return;

   // The shift: the entry candle closes beyond the micro structure that
   // contained the drop into the sweep.
   int shift_to = MathMin(copied - 2, 2 + MathMax(3, InpShiftLookback));
   bool shifted = false;
   if(direction == 1)
   {
      double micro_high = e[2].high;
      for(int i = 3; i <= shift_to; i++)
         micro_high = MathMax(micro_high, e[i].high);
      shifted = e[1].close > micro_high && e[1].close > e[1].open && BodyRatio(e[1]) >= 0.50;
   }
   else
   {
      double micro_low = e[2].low;
      for(int i = 3; i <= shift_to; i++)
         micro_low = MathMin(micro_low, e[i].low);
      shifted = e[1].close < micro_low && e[1].close < e[1].open && BodyRatio(e[1]) >= 0.50;
   }
   if(!shifted)
      return;

   s.valid = true;
   s.direction = direction;
   s.setup = (direction == 1) ? "SweepShiftBuy" : "SweepShiftSell";
   s.score = InpSweepScore;
   s.sl = sweep_extreme;
   s.reason = "liquidity sweep at the " + where + ", M1 structure shift confirmed by the entry candle";
}

// SR bounce at the clustered boundary; a sweep of the boundary adds points.
void BuildSRBounce(const MqlRates &e[], int copied, double atr15, int direction, ScalpSignal &s)
{
   EmptySignal(s);
   if(!TradeDirectionOK(direction))
      return;
   if(!LocationOK(direction, e[1].close))
      return;

   double level = (direction == 1) ? g_range_low : g_range_high;
   double width = (direction == 1) ? g_low_width : g_high_width;
   int touches = (direction == 1) ? g_low_touches : g_high_touches;
   if(level <= 0.0 || touches < MathMax(2, InpClusterMinTouches))
      return;

   if(direction == 1)
   {
      bool touched = e[1].low <= level + width && e[1].close > level - width;
      bool rejected = IsBullishPin(e[1]) || IsBullishEngulf(e, 1) ||
                      (e[1].close > e[1].open && LowerWick(e[1]) >= Body(e[1]));
      if(!touched || !rejected)
         return;
      s.sl = level - width;
      s.setup = "SRBounceBuy";
      s.reason = "range low (" + IntegerToString(touches) + " dips) rejected";
      if(e[1].low < level - width)
      {
         s.score = InpSRScore + 3.0;
         s.reason = s.reason + " after sweeping it";
         s.sl = e[1].low;
      }
      else
         s.score = InpSRScore;
   }
   else
   {
      bool touched = e[1].high >= level - width && e[1].close < level + width;
      bool rejected = IsBearishPin(e[1]) || IsBearishEngulf(e, 1) ||
                      (e[1].close < e[1].open && UpperWick(e[1]) >= Body(e[1]));
      if(!touched || !rejected)
         return;
      s.sl = level + width;
      s.setup = "SRBounceSell";
      s.reason = "range high (" + IntegerToString(touches) + " peaks) rejected";
      if(e[1].high > level + width)
      {
         s.score = InpSRScore + 3.0;
         s.reason = s.reason + " after sweeping it";
         s.sl = e[1].high;
      }
      else
         s.score = InpSRScore;
   }
   s.valid = true;
   s.direction = direction;
   s.score += MathMin(4.0, (touches - InpClusterMinTouches) * 1.0);
   if(g_bias == direction)
      s.score += 2.0;
}

// First return into the fresh order block (M5-refined boundary preferred).
void BuildOBScalp(const MqlRates &e[], int copied, int direction, ScalpSignal &s)
{
   EmptySignal(s);
   if(!TradeDirectionOK(direction))
      return;
   if(!LocationOK(direction, e[1].close))
      return;

   LevelZone z = ActiveOB(direction);
   if(!z.valid)
      return;
   double mid = (z.low + z.high) * 0.5;
   bool refined = (direction == 1) ? g_ob_bull_ref.valid : g_ob_bear_ref.valid;

   if(direction == 1)
   {
      bool touched = e[1].low <= z.high && e[1].close > mid;
      bool rej = IsBullishPin(e[1]) || IsBullishEngulf(e, 1) ||
                 (e[1].close > e[1].open && LowerWick(e[1]) >= Body(e[1]));
      if(!touched || !rej)
         return;
      s.sl = z.low;
      s.setup = "OBScalpBuy";
      s.reason = refined ? "first return into the M5-refined bullish order block held"
                         : "first return into the fresh bullish order block held";
   }
   else
   {
      bool touched = e[1].high >= z.low && e[1].close < mid;
      bool rej = IsBearishPin(e[1]) || IsBearishEngulf(e, 1) ||
                 (e[1].close < e[1].open && UpperWick(e[1]) >= Body(e[1]));
      if(!touched || !rej)
         return;
      s.sl = z.high;
      s.setup = "OBScalpSell";
      s.reason = refined ? "first return into the M5-refined bearish order block held"
                         : "first return into the fresh bearish order block held";
   }
   s.valid = true;
   s.direction = direction;
   s.score = InpOBScore + (refined ? 2.0 : 0.0) + (g_bias == direction ? 2.0 : 0.0);
}

// First return into the fresh M5 fair value gap.
void BuildFVGScalp(const MqlRates &e[], int copied, int direction, ScalpSignal &s)
{
   EmptySignal(s);
   if(!TradeDirectionOK(direction))
      return;
   if(!LocationOK(direction, e[1].close))
      return;

   LevelZone z = (direction == 1) ? g_fvg_bull : g_fvg_bear;
   if(!z.valid)
      return;
   double mid = (z.low + z.high) * 0.5;

   if(direction == 1)
   {
      bool touched = e[1].low <= z.high && e[1].close > mid;
      bool rej = IsBullishPin(e[1]) || IsBullishEngulf(e, 1) ||
                 (e[1].close > e[1].open && BodyRatio(e[1]) >= 0.50);
      if(!touched || !rej)
         return;
      s.sl = z.low;
      s.setup = "FVGScalpBuy";
      s.reason = "first return into the fresh M5 bullish FVG held";
   }
   else
   {
      bool touched = e[1].high >= z.low && e[1].close < mid;
      bool rej = IsBearishPin(e[1]) || IsBearishEngulf(e, 1) ||
                 (e[1].close < e[1].open && BodyRatio(e[1]) >= 0.50);
      if(!touched || !rej)
         return;
      s.sl = z.high;
      s.setup = "FVGScalpSell";
      s.reason = "first return into the fresh M5 bearish FVG held";
   }
   s.valid = true;
   s.direction = direction;
   s.score = InpFVGScore + (g_bias == direction ? 2.0 : 0.0);
}

// M1 break of structure retested and held (the proven earner).
void BuildBOSRetest(const MqlRates &e[], int copied, double atr15, ScalpSignal &s)
{
   EmptySignal(s);
   int direction = (g_bias != 0) ? g_bias : g_dir30;
   if(direction == 0 || !TradeDirectionOK(direction))
      return;
   if(!LocationOK(direction, e[1].close))
      return;

   int look = MathMax(4, InpBOSLookback);
   if(copied < look + 10)
      return;
   double tol = atr15 * 0.10;

   if(direction == 1)
   {
      for(int b = 2; b <= 6; b++)
      {
         double hh = e[b + 1].high;
         for(int i = b + 2; i <= b + look; i++)
            hh = MathMax(hh, e[i].high);
         if(e[b].close <= hh || BodyRatio(e[b]) < 0.55)
            continue;
         bool retest = e[1].low <= hh + tol && e[1].close > hh;
         bool rej = IsBullishPin(e[1]) || IsBullishEngulf(e, 1) ||
                    (e[1].close > e[1].open && LowerWick(e[1]) >= Body(e[1]));
         if(retest && rej)
         {
            s.valid = true;
            s.direction = 1;
            s.setup = "BOSRetestBuy";
            s.score = InpBOSRetestScore;
            s.sl = MathMin(hh, e[1].low);
            s.reason = "M1 structure break retested and held as support";
         }
         return;
      }
   }
   else
   {
      for(int b = 2; b <= 6; b++)
      {
         double ll = e[b + 1].low;
         for(int i = b + 2; i <= b + look; i++)
            ll = MathMin(ll, e[i].low);
         if(e[b].close >= ll || BodyRatio(e[b]) < 0.55)
            continue;
         bool retest = e[1].high >= ll - tol && e[1].close < ll;
         bool rej = IsBearishPin(e[1]) || IsBearishEngulf(e, 1) ||
                    (e[1].close < e[1].open && UpperWick(e[1]) >= Body(e[1]));
         if(retest && rej)
         {
            s.valid = true;
            s.direction = -1;
            s.setup = "BOSRetestSell";
            s.score = InpBOSRetestScore;
            s.sl = MathMax(ll, e[1].high);
            s.reason = "M1 structure break retested and held as resistance";
         }
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Basket engine: 2-4 legs, shared stop, laddered take-profits      |
//+------------------------------------------------------------------+
int LegsForScore(double score)
{
   if(score >= 88.0) return ClampInt(InpLegsStrongSignal, 1, 4);
   if(score >= 80.0) return ClampInt(InpLegsGoodSignal, 1, 4);
   return ClampInt(InpLegsBaseSignal, 1, 4);
}

void OpenBasket(ScalpSignal &signal)
{
   int direction = signal.direction;
   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr15 = GetATR(InpWorkingTF, 1);
   if(atr15 <= 0.0)
      return;

   double buffer = atr15 * MathMax(0.05, InpStopBufferATR) +
                   (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double sl = (direction == 1) ? signal.sl - buffer : signal.sl + buffer;
   double distance = MathAbs(entry - sl);
   double floor_d = atr15 * MathMax(0.10, InpMinStopATR);
   double cap_d = atr15 * MathMax(InpMinStopATR + 0.05, InpMaxStopATR);
   if(distance < floor_d)
   {
      distance = floor_d;
      sl = entry - direction * distance;
   }
   if(distance > cap_d)
   {
      g_last_action = "Skipped " + signal.setup + ": stop wider than a scalp allows";
      if(InpVerboseLog) Print(g_last_action);
      return;
   }
   sl = NormalizePrice(sl);
   distance = MathAbs(entry - sl);
   if(!StopsLegal(direction, entry, sl))
   {
      g_last_action = "Skipped " + signal.setup + ": stop inside the broker minimum";
      return;
   }

   int legs = LegsForScore(signal.score);
   double total_risk_cash = RiskBudgetCash();
   if(total_risk_cash <= 0.0)
      return;

   double loss_per_lot = LossPerLot(direction, entry, sl);
   if(loss_per_lot <= 0.0)
      return;

   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double leg_vol = 0.0;
   while(legs >= 1)
   {
      leg_vol = NormalizeVolumeDown(total_risk_cash / legs / loss_per_lot);
      if(leg_vol >= min_vol)
         break;
      legs--;
   }
   if(legs < 1)
   {
      double min_risk_pct = min_vol * loss_per_lot * 100.0 / MathMax(1.0, AccountInfoDouble(ACCOUNT_EQUITY));
      if(min_risk_pct > MathMax(0.01, InpMinLotMaxRiskPercent))
      {
         g_last_action = "Skipped " + signal.setup + ": minimum lot risks " +
                         DoubleToString(min_risk_pct, 2) + "% of equity";
         if(InpVerboseLog) Print(g_last_action);
         return;
      }
      legs = 1;
      leg_vol = min_vol;
   }
   if(InpMaxLotPerLeg > 0.0)
      leg_vol = MathMin(leg_vol, NormalizeVolumeDown(InpMaxLotPerLeg));
   if(leg_vol < min_vol)
      return;

   double margin = 0.0;
   ENUM_ORDER_TYPE type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(type, _Symbol, leg_vol * legs, entry, margin) ||
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.90)
   {
      g_last_action = "Skipped " + signal.setup + ": not enough free margin for the basket";
      return;
   }

   double ladder[4];
   ladder[0] = MathMax(0.3, InpTP1R);
   ladder[1] = MathMax(ladder[0], InpTP2R);
   ladder[2] = MathMax(ladder[1], InpTP3R);
   ladder[3] = MathMax(ladder[2], InpTP4R);

   int opened = 0;
   for(int i = 0; i < legs; i++)
   {
      double tp = NormalizePrice(entry + direction * distance * ladder[i]);
      string comment = "NSMC|" + signal.setup;
      if(StringLen(comment) > 27)
         comment = StringSubstr(comment, 0, 27);
      comment = comment + "|" + IntegerToString(i + 1);
      bool ok = trade.PositionOpen(_Symbol, type, leg_vol, entry, sl, tp, comment);
      if(ok)
         opened++;
      else if(InpVerboseLog)
         Print("Leg ", i + 1, " failed: ", (int)trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   if(opened == 0)
      return;

   g_basket_dir = direction;
   g_basket_entry = entry;
   g_basket_risk = distance;
   g_basket_time = TimeCurrent();
   g_basket_legs = opened;
   g_basket_be_done = false;
   g_basket_peak_r = 0.0;
   g_day_baskets++;

   g_last_action = signal.setup + " (" + DoubleToString(signal.score, 1) + "): " +
                   IntegerToString(opened) + " legs, TP ladder to " +
                   DoubleToString(ladder[MathMin(opened, 4) - 1], 1) + "R";
   if(InpVerboseLog)
      Print(g_last_action, " | ", signal.reason);
}

void ManageBasket()
{
   int count = CountOurPositions();
   if(count == 0)
   {
      if(g_basket_dir != 0)
      {
         g_last_basket_close = TimeCurrent();
         g_basket_dir = 0;
         g_basket_legs = 0;
         g_basket_be_done = false;
         g_basket_peak_r = 0.0;
      }
      return;
   }
   if(g_basket_dir == 0 || g_basket_risk <= 0.0)
      return;

   double current = (g_basket_dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double rr = (current - g_basket_entry) * g_basket_dir / g_basket_risk;
   if(rr > g_basket_peak_r)
      g_basket_peak_r = rr;

   bool first_leg_banked = count < g_basket_legs;
   if(!g_basket_be_done && (rr >= MathMax(0.3, InpBasketBreakEvenAtR) || first_leg_banked))
   {
      double cost = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      double be = NormalizePrice(g_basket_entry + g_basket_dir * cost);
      MoveBasketStops(be);
      g_basket_be_done = true;
      g_last_action = "Basket protected at break-even";
   }

   // V8.10 (from ASQ, re-expressed in R): once armed, the remaining legs
   // trail behind the peak so a runner banks most of what it reaches.
   if(InpUseRunnerTrail && g_basket_be_done &&
      g_basket_peak_r >= MathMax(0.5, InpTrailStartR))
   {
      double trail_r = g_basket_peak_r - MathMax(0.2, InpTrailStepR);
      if(trail_r > 0.0)
      {
         double trail_sl = NormalizePrice(g_basket_entry + g_basket_dir * trail_r * g_basket_risk);
         MoveBasketStops(trail_sl);
      }
   }

   if(g_basket_peak_r >= MathMax(0.3, InpGivebackArmR) &&
      rr <= MathMax(0.0, InpGivebackFloorR))
   {
      CloseBasket("giveback guard banked the scalp at +" + DoubleToString(MathMax(rr, 0.0), 2) + "R");
      return;
   }

   if(InpMaxHoldMinutes > 0 &&
      TimeCurrent() - g_basket_time > (long)InpMaxHoldMinutes * 60)
   {
      CloseBasket("time exit after " + IntegerToString(InpMaxHoldMinutes) + " minutes");
      return;
   }

   if(InpExitOnDirectionFlip &&
      (g_bias == -g_basket_dir || g_dir30 == -g_basket_dir))
      CloseBasket("higher-timeframe direction flipped against the basket");
}

void MoveBasketStops(double new_sl)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      bool improves = (g_basket_dir == 1) ? new_sl > sl + _Point : new_sl < sl - _Point;
      if(improves)
         trade.PositionModify(ticket, new_sl, tp);
   }
}

void CloseBasket(string why)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      trade.PositionClose(ticket);
   }
   g_last_action = "Basket closed: " + why;
   if(InpVerboseLog)
      Print(g_last_action);
}

//+------------------------------------------------------------------+
//| Risk, sizing, daily limits                                       |
//+------------------------------------------------------------------+
double RiskBudgetCash()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_base = equity;
   if(InpMaxDrawdownPercent > 0.0)
      risk_base = MathMax(0.0, equity - MathMax(balance, equity) * InpMaxDrawdownPercent / 100.0);
   double pct = MathMin(MathMax(0.01, InpRiskPercent), MathMax(0.01, InpMaxRiskPercent));
   return risk_base * pct / 100.0;
}

double LossPerLot(int direction, double entry, double sl)
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lpl = 0.0;
   if(tick_value > 0.0 && tick_size > 0.0)
      lpl = MathAbs(entry - sl) / tick_size * tick_value;
   double calc = 0.0;
   if(OrderCalcProfit((direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, entry, sl, calc))
      lpl = MathMax(lpl, MathAbs(calc));
   return lpl;
}

void ResetDailyState()
{
   g_day_start = StartOfDay(TimeCurrent());
   g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_locked = false;
   g_lock_reason = "";
   g_day_baskets = 0;
}

void ResetDailyStateIfNeeded()
{
   if(StartOfDay(TimeCurrent()) != g_day_start)
      ResetDailyState();
}

void CheckDailyLimits()
{
   double closed = TodayClosedProfit();
   double open_pl = OpenProfit();
   double day = closed + open_pl;

   if(!g_daily_locked && InpDailyLossLimitPercent > 0.0 &&
      day <= -g_day_start_equity * InpDailyLossLimitPercent / 100.0)
   {
      g_daily_locked = true;
      g_lock_reason = "Daily loss limit";
   }
   if(!g_daily_locked && InpDailyProfitTargetPct > 0.0 &&
      day >= g_day_start_equity * InpDailyProfitTargetPct / 100.0)
   {
      g_daily_locked = true;
      g_lock_reason = "Daily profit target banked";
   }
   if(g_daily_locked && InpCloseAllAtDailyLock && CountOurPositions() > 0)
      CloseBasket(g_lock_reason);
}

double TodayClosedProfit()
{
   double profit = 0.0;
   if(!HistorySelect(g_day_start, TimeCurrent()))
      return 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || (long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      long dentry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(dentry != DEAL_ENTRY_OUT && dentry != DEAL_ENTRY_OUT_BY && dentry != DEAL_ENTRY_INOUT)
         continue;
      profit += HistoryDealGetDouble(deal, DEAL_PROFIT) +
                HistoryDealGetDouble(deal, DEAL_SWAP) +
                HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
   return profit;
}

double OpenProfit()
{
   double p = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      p += PositionGetDouble(POSITION_PROFIT);
   }
   return p;
}

//+------------------------------------------------------------------+
//| Environment checks                                               |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0)
      return true;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (int)MathRound((ask - bid) / _Point) <= InpMaxSpreadPoints;
}

bool DirectionAllowed(int direction)
{
   if(!InpUseBoomCrashFilter)
      return true;
   string s = _Symbol;
   StringToLower(s);
   if(StringFind(s, "boom") >= 0 && direction != 1) return false;
   if(StringFind(s, "crash") >= 0 && direction != -1) return false;
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_LONGONLY && direction != 1) return false;
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY && direction != -1) return false;
   return true;
}

bool StopsLegal(int direction, double entry, double sl)
{
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double min_dist = MathMax((double)MathMax(stops_level, freeze) * _Point + spread, 2.0 * _Point);
   return MathAbs(entry - sl) >= min_dist;
}

int CountOurPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      c++;
   }
   return c;
}

//+------------------------------------------------------------------+
//| Structure and candle helpers                                     |
//+------------------------------------------------------------------+
bool IsSwingHigh(const MqlRates &r[], int copied, int index, int depth)
{
   if(index < depth || index + depth >= copied)
      return false;
   for(int i = 1; i <= depth; i++)
      if(r[index].high <= r[index - i].high || r[index].high <= r[index + i].high)
         return false;
   return true;
}

bool IsSwingLow(const MqlRates &r[], int copied, int index, int depth)
{
   if(index < depth || index + depth >= copied)
      return false;
   for(int i = 1; i <= depth; i++)
      if(r[index].low >= r[index - i].low || r[index].low >= r[index + i].low)
         return false;
   return true;
}

void FindLastTwoSwings(const MqlRates &r[], int copied, int depth, int direction,
                       int &last_idx, int &prev_idx)
{
   last_idx = -1;
   prev_idx = -1;
   for(int i = depth + 1; i < copied - depth; i++)
   {
      bool swing = (direction == 1) ? IsSwingLow(r, copied, i, depth)
                                    : IsSwingHigh(r, copied, i, depth);
      if(!swing)
         continue;
      if(last_idx < 0)
         last_idx = i;
      else
      {
         prev_idx = i;
         return;
      }
   }
}

double Body(const MqlRates &b) { return MathAbs(b.close - b.open); }
double Range(const MqlRates &b) { return MathMax(b.high - b.low, _Point); }
double UpperWick(const MqlRates &b) { return b.high - MathMax(b.open, b.close); }
double LowerWick(const MqlRates &b) { return MathMin(b.open, b.close) - b.low; }
double BodyRatio(const MqlRates &b) { return Body(b) / Range(b); }

bool IsBullishPin(const MqlRates &b)
{
   return LowerWick(b) >= 2.0 * MathMax(Body(b), _Point) &&
          UpperWick(b) <= 0.15 * Range(b) &&
          b.close > b.low + 0.65 * Range(b);
}

bool IsBearishPin(const MqlRates &b)
{
   return UpperWick(b) >= 2.0 * MathMax(Body(b), _Point) &&
          LowerWick(b) <= 0.15 * Range(b) &&
          b.close < b.low + 0.35 * Range(b);
}

bool IsBullishEngulf(const MqlRates &r[], int i)
{
   return r[i + 1].close < r[i + 1].open && r[i].close > r[i].open &&
          r[i].close >= r[i + 1].open && r[i].open <= r[i + 1].close;
}

bool IsBearishEngulf(const MqlRates &r[], int i)
{
   return r[i + 1].close > r[i + 1].open && r[i].close < r[i].open &&
          r[i].close <= r[i + 1].open && r[i].open >= r[i + 1].close;
}

//+------------------------------------------------------------------+
//| Indicator wrappers                                               |
//+------------------------------------------------------------------+
double GetATR(ENUM_TIMEFRAMES tf, int shift)
{
   int handle = iATR(_Symbol, tf, MathMax(2, InpATRPeriod));
   if(handle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   int copied = CopyBuffer(handle, 0, shift, 1, buf);
   IndicatorRelease(handle);
   return (copied == 1) ? buf[0] : 0.0;
}

double GetAverageATR(ENUM_TIMEFRAMES tf, int bars)
{
   int handle = iATR(_Symbol, tf, MathMax(2, InpATRPeriod));
   if(handle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   int copied = CopyBuffer(handle, 0, 1, MathMax(10, bars), buf);
   IndicatorRelease(handle);
   if(copied <= 0) return 0.0;
   double sum = 0.0;
   for(int i = 0; i < copied; i++) sum += buf[i];
   return sum / copied;
}

//+------------------------------------------------------------------+
//| Small utilities                                                  |
//+------------------------------------------------------------------+
void EmptySignal(ScalpSignal &s)
{
   s.valid = false;
   s.direction = 0;
   s.score = 0.0;
   s.setup = "";
   s.reason = "";
   s.sl = 0.0;
}

void KeepBetter(ScalpSignal &best, const ScalpSignal &candidate)
{
   if(candidate.valid && (!best.valid || candidate.score > best.score))
      best = candidate;
}

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &storage)
{
   datetime t = iTime(_Symbol, tf, 0);
   if(t <= 0) return false;
   if(t != storage)
   {
      storage = t;
      return true;
   }
   return false;
}

datetime StartOfDay(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

double NormalizePrice(double p) { return NormalizeDouble(p, _Digits); }

double NormalizeVolumeDown(double v)
{
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = min_vol;
   if(v < min_vol) return 0.0;
   v = MathMin(max_vol, MathFloor(v / step) * step);
   int digits = 2;
   if(step < 0.01) digits = 3;
   if(step < 0.001) digits = 4;
   return NormalizeDouble(v, digits);
}

int ClampInt(int v, int lo, int hi) { return (int)MathMax(lo, MathMin(hi, v)); }

//+------------------------------------------------------------------+
//| Visuals: PD bands, range lines, structure marks                  |
//+------------------------------------------------------------------+
void DrawWorkingChart()
{
   datetime end = iTime(_Symbol, InpWorkingTF, 0) +
                  (datetime)(PeriodSeconds(InpWorkingTF) * 12);

   // ---- Premium / Equilibrium / Discount bands ----
   if(InpShowPDBands && g_range_high > 0.0 && g_range_low > 0.0 && g_range_high > g_range_low)
   {
      double range = g_range_high - g_range_low;
      double ext = range * MathMax(1.0, InpExtremeBandPercent) / 100.0;
      double eq_half = range * MathMax(1.0, InpPDBandPercent) / 200.0;

      DrawRectZone("NSMC_PD_P", g_range_start, g_range_high, end, g_range_high - ext,
                   C'205,224,242', "Premium", C'70,75,80');
      DrawRectZone("NSMC_PD_E", g_range_start, g_equilibrium + eq_half, end, g_equilibrium - eq_half,
                   C'212,212,212', "Equilibrium", C'70,75,80');
      DrawRectZone("NSMC_PD_D", g_range_start, g_range_low + ext, end, g_range_low,
                   C'196,193,120', "Discount", C'70,75,80');
   }
   else
   {
      DeleteZone("NSMC_PD_P");
      DeleteZone("NSMC_PD_E");
      DeleteZone("NSMC_PD_D");
   }

   // ---- Range boundary lines: Weak/Strong High and Low ----
   if(InpShowRangeLines && g_range_high > 0.0)
   {
      DrawSegment("NSMC_RH", g_range_start, g_range_high, end, STYLE_SOLID, C'165,55,135', 2);
      DrawTextAt("NSMC_RH_L", end, g_range_high,
                 g_high_swept ? "Strong High" : "Weak High", C'165,55,135', 9);
   }
   else
   {
      ObjectDelete(0, "NSMC_RH");
      ObjectDelete(0, "NSMC_RH_L");
   }
   if(InpShowRangeLines && g_range_low > 0.0)
   {
      DrawSegment("NSMC_RL", g_range_start, g_range_low, end, STYLE_SOLID, C'20,150,90', 2);
      DrawTextAt("NSMC_RL_L", end, g_range_low,
                 g_low_swept ? "Strong Low" : "Weak Low", C'20,150,90', 9);
   }
   else
   {
      ObjectDelete(0, "NSMC_RL");
      ObjectDelete(0, "NSMC_RL_L");
   }

   // ---- BOS / CHoCH / EQL / EQH marks ----
   DeleteByPrefix("NSMC_MK");
   if(InpShowStructureMarks)
   {
      for(int i = 0; i < MAX_MARKS; i++)
      {
         if(!g_marks[i].valid)
            continue;
         string base = "NSMC_MK" + IntegerToString(i);
         color clr = (g_marks[i].kind >= 3) ? C'0,145,145'
                     : (g_marks[i].direction == 1 ? C'40,150,90' : C'200,60,50');
         ENUM_LINE_STYLE style = (g_marks[i].kind >= 3) ? STYLE_DOT : STYLE_DASH;
         DrawSegment(base, g_marks[i].t_from, g_marks[i].level, g_marks[i].t_to, style, clr, 1);
         string txt = (g_marks[i].kind == 1) ? "BOS"
                      : (g_marks[i].kind == 2) ? "CHoCH"
                      : (g_marks[i].kind == 3) ? "EQL" : "EQH";
         string prefix = (g_marks[i].kind <= 2)
                         ? (g_marks[i].direction == 1 ? "Bullish " : "Bearish ") : "";
         DrawTextAt(base + "_T", g_marks[i].t_to, g_marks[i].level, prefix + txt, clr, 8);
      }
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Visuals: order block and FVG zones                               |
//+------------------------------------------------------------------+
void DrawZones()
{
   datetime end = iTime(_Symbol, InpWorkingTF, 0) +
                  (datetime)(PeriodSeconds(InpWorkingTF) * 12);

   LevelZone bull = ActiveOB(1);
   LevelZone bear = ActiveOB(-1);
   if(InpUseOrderBlocks && bull.valid)
      DrawRectZone("NSMC_OB_B", bull.start, bull.high, end, bull.low,
                   C'198,236,205', "Bullish OB", C'30,90,55');
   else
      DeleteZone("NSMC_OB_B");
   if(InpUseOrderBlocks && bear.valid)
      DrawRectZone("NSMC_OB_S", bear.start, bear.high, end, bear.low,
                   C'250,205,190', "Bearish OB", C'120,45,30');
   else
      DeleteZone("NSMC_OB_S");

   if(InpUseFVG && g_fvg_bull.valid)
      DrawRectZone("NSMC_FVG_B", g_fvg_bull.start, g_fvg_bull.high, end, g_fvg_bull.low,
                   C'214,238,252', "Bullish FVG", C'40,80,120');
   else
      DeleteZone("NSMC_FVG_B");
   if(InpUseFVG && g_fvg_bear.valid)
      DrawRectZone("NSMC_FVG_S", g_fvg_bear.start, g_fvg_bear.high, end, g_fvg_bear.low,
                   C'255,228,214', "Bearish FVG", C'130,60,35');
   else
      DeleteZone("NSMC_FVG_S");

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Drawing primitives                                               |
//+------------------------------------------------------------------+
void DrawRectZone(string name, datetime t1, double p_top, datetime t2, double p_bottom,
                  color fill, string label, color label_clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p_top, t2, p_bottom);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p_top);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p_bottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   string ln = name + "_L";
   double mid = (p_top + p_bottom) * 0.5;
   if(ObjectFind(0, ln) < 0)
      ObjectCreate(0, ln, OBJ_TEXT, 0, t2, mid);
   ObjectSetInteger(0, ln, OBJPROP_TIME, t2);
   ObjectSetDouble(0, ln, OBJPROP_PRICE, mid);
   ObjectSetString(0, ln, OBJPROP_TEXT, label);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, label_clr);
   ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, ln, OBJPROP_ANCHOR, ANCHOR_RIGHT);
   ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
}

void DeleteZone(string name)
{
   ObjectDelete(0, name);
   ObjectDelete(0, name + "_L");
}

void DrawSegment(string name, datetime t1, double price, datetime t2,
                 ENUM_LINE_STYLE style, color clr, int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawTextAt(string name, datetime t, double price, string text, color clr, int size)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   if(!InpShowDashboard)
      return;
   static datetime last_draw = 0;
   if(TimeCurrent() - last_draw < 2)
      return;
   last_draw = TimeCurrent();

   int x = InpDashboardX, y = InpDashboardY;
   Panel("NSMC_Panel", x, y, 372, 322);
   Label("NSMC_T", x + 12, y + 10, "NDLOVU SMC MASTER V8.11", C'255,255,255', 11);

   int spread_pts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Label("NSMC_S", x + 12, y + 32,
         _Symbol + "  |  " + EnumToString(InpEntryTF) + " trigger  |  spread " +
         IntegerToString(spread_pts) + " pts",
         C'155,205,255', 8);

   string bias = (g_bias == 1) ? "Bullish" : (g_bias == -1) ? "Bearish" : "Ranging";
   string dir30 = (g_dir30 == 1) ? "Bullish" : (g_dir30 == -1) ? "Bearish" : "Flat";
   color bc = (g_bias == 1) ? C'120,235,170' : (g_bias == -1) ? C'255,140,120' : C'210,210,160';
   Label("NSMC_B", x + 12, y + 54,
         "H1: " + bias + "  |  M30: " + dir30 + (g_expansion ? "  |  EXPANSION" : ""), bc, 9);

   string mom;
   color mc = C'170,175,180';
   if(!InpUseMomentumEngine)
      mom = "Momentum engine: off";
   else if(g_mom_bull_ok || g_mom_bear_ok)
   {
      string tier = (g_mom_strength >= 2) ? "Strong" : (g_mom_strength == 1) ? "Moderate" : "Weak";
      mom = "Momentum: " + string(g_mom_bull_ok ? "Bullish" : "Bearish") +
            " (" + tier + ")  RSI " + DoubleToString(g_mom_rsi, 0);
      mc = g_mom_bull_ok ? C'120,235,170' : C'255,140,120';
   }
   else
      mom = "Momentum: neutral  RSI " + DoubleToString(g_mom_rsi, 0);
   Label("NSMC_M", x + 12, y + 76, mom, mc, 9);

   string range_info = "Range: ";
   if(g_range_high > 0.0 && g_range_low > 0.0)
      range_info += DoubleToString(g_range_low, _Digits) + " (" +
                    (g_low_swept ? "strong" : "weak") + ") - " +
                    DoubleToString(g_range_high, _Digits) + " (" +
                    (g_high_swept ? "strong" : "weak") + ")";
   else
      range_info += "building";
   Label("NSMC_R", x + 12, y + 98, range_info, C'170,190,210', 8);

   LevelZone obb = ActiveOB(1);
   LevelZone obs = ActiveOB(-1);
   string zones = "OB: ";
   zones += obb.valid ? string(g_ob_bull_ref.valid ? "bull(M5)" : "bull") : "-";
   zones += " / ";
   zones += obs.valid ? string(g_ob_bear_ref.valid ? "bear(M5)" : "bear") : "-";
   zones += "   FVG: ";
   zones += g_fvg_bull.valid ? "bull" : "-";
   zones += " / ";
   zones += g_fvg_bear.valid ? "bear" : "-";
   Label("NSMC_Z", x + 12, y + 120, zones, C'170,175,180', 8);

   string basket;
   color kc = C'180,210,255';
   int legs_now = CountOurPositions();
   if(legs_now > 0 && g_basket_dir != 0 && g_basket_risk > 0.0)
   {
      double current = (g_basket_dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double rr = (current - g_basket_entry) * g_basket_dir / g_basket_risk;
      long age_min = (TimeCurrent() - g_basket_time) / 60;
      basket = "Basket: " + IntegerToString(legs_now) + "/" + IntegerToString(g_basket_legs) +
               " legs " + (g_basket_dir == 1 ? "LONG" : "SHORT") +
               "  R " + DoubleToString(rr, 2) + " (peak " + DoubleToString(g_basket_peak_r, 2) + ")" +
               "  " + IntegerToString((int)age_min) + "m" +
               (g_basket_be_done ? "  BE" : "");
      kc = rr >= 0 ? C'120,235,170' : C'255,150,130';
   }
   else
      basket = "Basket: flat";
   Label("NSMC_K", x + 12, y + 142, basket, kc, 9);

   double closed = TodayClosedProfit();
   double open_pl = OpenProfit();
   double day = closed + open_pl;
   double day_pct = (g_day_start_equity > 0.0) ? day / g_day_start_equity * 100.0 : 0.0;
   Label("NSMC_P", x + 12, y + 164,
         "Today: " + DoubleToString(day, 2) + " (" + DoubleToString(day_pct, 2) + "%)" +
         "  |  Open: " + DoubleToString(open_pl, 2),
         day >= 0 ? C'120,235,170' : C'255,118,100', 9);

   string caps = "Baskets today: " + IntegerToString(g_day_baskets);
   if(InpMaxDayBaskets > 0)
      caps += " / " + IntegerToString(InpMaxDayBaskets);
   Label("NSMC_C", x + 12, y + 186, caps, C'170,190,210', 8);

   string dd_line = "Drawdown: " + DoubleToString(g_current_dd, 1) + "%  (peak " +
                    DoubleToString(g_peak_dd, 1) + "%";
   if(InpMaxDrawdownLockPct > 0.0)
      dd_line += ", lock " + DoubleToString(InpMaxDrawdownLockPct, 0) + "%";
   dd_line += ")";
   color dc = (InpMaxDrawdownLockPct > 0.0 && g_current_dd >= InpMaxDrawdownLockPct)
              ? C'255,118,100'
              : (g_current_dd > InpMaxDrawdownLockPct * 0.6 && InpMaxDrawdownLockPct > 0.0)
                ? C'255,205,120' : C'170,190,210';
   Label("NSMC_D", x + 12, y + 208, dd_line, dc, 8);

   string filters = "Session: " + string(!InpUseSessionFilter ? "off" : (SessionOK() ? "open" : "CLOSED")) +
                    "  |  News: " + string(!InpUseNewsFilter ? "off" : (NewsOK() ? "clear" : "BLOCKED"));
   Label("NSMC_F", x + 12, y + 230, filters, C'170,175,180', 8);

   Label("NSMC_L", x + 12, y + 252,
         g_daily_locked ? ("LOCKED - " + g_lock_reason) : "Trading: OPEN",
         g_daily_locked ? C'255,118,100' : C'120,235,170', 9);
   Label("NSMC_A", x + 12, y + 274, "Last: " + g_last_action, C'200,210,220', 8);
   Label("NSMC_V", x + 12, y + 296,
         "SMC hierarchy + ASQ momentum  |  no journal, no pendings", C'120,130,140', 7);
}

void Panel(string name, int x, int y, int w, int h)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'20,24,31');
   ObjectSetInteger(0, name, OBJPROP_COLOR, C'70,86,100');
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void Label(string name, int x, int y, string text, color clr, int size)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DeleteByPrefix(string prefix)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| V8.10 - ASQ momentum engine                                       |
//| Trend (EMA fast/slow) + strength (EMA separation vs ATR) +        |
//| price position + candle momentum + RSI window, cached per         |
//| engine-TF bar. This is the grader behind the confluence bonus     |
//| and the gate behind the momentum breakout setup.                  |
//+------------------------------------------------------------------+
void RefreshMomentum()
{
   static datetime last = 0;
   if(!InpUseMomentumEngine)
   {
      g_mom_bull_ok = false;
      g_mom_bear_ok = false;
      g_mom_strength = -1;
      return;
   }
   datetime bar = iTime(_Symbol, InpMomTF, 0);
   if(bar == last || bar <= 0)
      return;
   last = bar;

   g_mom_bull_ok = false;
   g_mom_bear_ok = false;
   g_mom_strength = -1;

   double ema_fast = GetMA(InpMomTF, InpMomEmaFast, 1);
   double ema_slow = GetMA(InpMomTF, InpMomEmaSlow, 1);
   double atr = GetATR(InpMomTF, 1);
   if(ema_fast <= 0.0 || ema_slow <= 0.0 || atr <= 0.0)
      return;

   double c1 = iClose(_Symbol, InpMomTF, 1);
   double c2 = iClose(_Symbol, InpMomTF, 2);
   if(c1 <= 0.0 || c2 <= 0.0)
      return;

   double sep = MathAbs(ema_fast - ema_slow);
   int tier = (sep >= atr * 0.6) ? 2 : (sep >= atr * 0.3) ? 1 : (sep >= atr * 0.1) ? 0 : -1;
   g_mom_strength = tier;
   g_mom_rsi = GetRSI(InpMomTF, InpMomRsiPeriod, 1);
   if(tier < (int)InpMomTrendStrength)
      return;   // the trend is not strong enough to grade anything

   bool bull_trend = ema_fast > ema_slow;
   bool above_both = c1 > ema_fast && c1 > ema_slow;
   bool below_both = c1 < ema_fast && c1 < ema_slow;
   bool bull_mom = c1 > c2;
   bool bear_mom = c1 < c2;
   bool rsi_buy = g_mom_rsi >= InpMomRsiBuyMin && g_mom_rsi <= InpMomRsiBuyMax;
   bool rsi_sell = g_mom_rsi >= InpMomRsiSellMin && g_mom_rsi <= InpMomRsiSellMax;

   g_mom_bull_ok = bull_trend && above_both && bull_mom && rsi_buy;
   g_mom_bear_ok = !bull_trend && below_both && bear_mom && rsi_sell;
}

//+------------------------------------------------------------------+
//| V8.10 - The ASQ 7-condition momentum breakout, integrated:        |
//| all engine conditions + N-bar breakout with an ATR buffer +       |
//| the SMC hierarchy direction gate. Deliberately EXEMPT from the    |
//| premium/discount location gate - a breakout is an expansion       |
//| beyond value by nature - but it refuses to break straight into    |
//| the clustered range boundary sitting overhead/underneath.         |
//+------------------------------------------------------------------+
void BuildMomentumBreakout(ScalpSignal &s)
{
   EmptySignal(s);
   datetime bar = iTime(_Symbol, InpMomTF, 1);
   if(bar <= 0 || bar == g_last_breakout_fire)
      return;   // one attempt per closed engine bar

   MqlRates m[];
   ArraySetAsSeries(m, true);
   int need = MathMax(26, InpBreakoutLookback + 6);
   int copied = CopyRates(_Symbol, InpMomTF, 0, need, m);
   if(copied < InpBreakoutLookback + 4)
      return;

   double atr = GetATR(InpMomTF, 1);
   double atr15 = GetATR(InpWorkingTF, 1);
   if(atr <= 0.0 || atr15 <= 0.0)
      return;
   double buf = atr * MathMax(0.05, InpBreakoutBufferATR);

   double hi_h = m[2].high, lo_l = m[2].low;
   for(int i = 2; i <= InpBreakoutLookback + 1; i++)
   {
      hi_h = MathMax(hi_h, m[i].high);
      lo_l = MathMin(lo_l, m[i].low);
   }

   if(g_mom_bull_ok && TradeDirectionOK(1) &&
      m[1].close > hi_h - buf && m[2].close <= hi_h)
   {
      // Never break INTO the clustered range high just overhead.
      if(g_range_high > 0.0 && g_range_high > m[1].close &&
         g_range_high - m[1].close < atr15 * 0.30)
         return;
      s.valid = true;
      s.direction = 1;
      s.setup = "MomBreakoutBuy";
      s.score = InpMomBreakoutScore +
                ((g_mom_strength >= 2) ? 4.0 : (g_mom_strength == 1) ? 2.0 : 0.0) +
                ((g_bias == 1) ? 2.0 : 0.0);
      s.sl = m[1].low;
      s.reason = "7-condition momentum breakout above the " +
                 IntegerToString(InpBreakoutLookback) + "-bar high";
      g_last_breakout_fire = bar;
      return;
   }

   if(g_mom_bear_ok && TradeDirectionOK(-1) &&
      m[1].close < lo_l + buf && m[2].close >= lo_l)
   {
      if(g_range_low > 0.0 && g_range_low < m[1].close &&
         m[1].close - g_range_low < atr15 * 0.30)
         return;
      s.valid = true;
      s.direction = -1;
      s.setup = "MomBreakoutSell";
      s.score = InpMomBreakoutScore +
                ((g_mom_strength >= 2) ? 4.0 : (g_mom_strength == 1) ? 2.0 : 0.0) +
                ((g_bias == -1) ? 2.0 : 0.0);
      s.sl = m[1].high;
      s.reason = "7-condition momentum breakout below the " +
                 IntegerToString(InpBreakoutLookback) + "-bar low";
      g_last_breakout_fire = bar;
   }
}

//+------------------------------------------------------------------+
//| V8.10 - Peak drawdown guard (persists across restarts)            |
//+------------------------------------------------------------------+
void UpdateDrawdownGuard()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > g_peak_balance)
      g_peak_balance = balance;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_current_dd = (g_peak_balance > 0.0)
                  ? (g_peak_balance - equity) / g_peak_balance * 100.0 : 0.0;
   if(g_current_dd < 0.0)
      g_current_dd = 0.0;
   if(g_current_dd > g_peak_dd)
   {
      g_peak_dd = g_current_dd;
      if(!MQLInfoInteger(MQL_TESTER) && g_gv_peak_dd != "")
         GlobalVariableSet(g_gv_peak_dd, g_peak_dd);
   }
}

//+------------------------------------------------------------------+
//| V8.10 - Session and manual news filters (for real markets)        |
//+------------------------------------------------------------------+
bool SessionOK()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return false;
   if(InpAvoidFridayClose && dt.day_of_week == 5 && dt.hour >= InpFridayCutoffHour)
      return false;
   return dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour;
}

bool NewsOK()
{
   datetime now = TimeCurrent();
   if(InNewsWindow(InpNewsTime1, now)) return false;
   if(InNewsWindow(InpNewsTime2, now)) return false;
   if(InNewsWindow(InpNewsTime3, now)) return false;
   return true;
}

bool InNewsWindow(string time_text, datetime now)
{
   if(time_text == "" || StringLen(time_text) < 4)
      return false;
   int colon = StringFind(time_text, ":");
   if(colon < 0)
      return false;
   int nh = (int)StringToInteger(StringSubstr(time_text, 0, colon));
   int nm = (int)StringToInteger(StringSubstr(time_text, colon + 1));
   MqlDateTime d;
   TimeToStruct(now, d);
   d.hour = nh;
   d.min = nm;
   d.sec = 0;
   datetime nt = StructToTime(d);
   return now >= nt - (long)InpNewsMinsBefore * 60 &&
          now <= nt + (long)InpNewsMinsAfter * 60;
}

//+------------------------------------------------------------------+
//| V8.10 - Extra indicator wrappers                                  |
//+------------------------------------------------------------------+
double GetMA(ENUM_TIMEFRAMES tf, int period, int shift)
{
   int handle = iMA(_Symbol, tf, MathMax(2, period), 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   int copied = CopyBuffer(handle, 0, shift, 1, buf);
   IndicatorRelease(handle);
   return (copied == 1) ? buf[0] : 0.0;
}

double GetRSI(ENUM_TIMEFRAMES tf, int period, int shift)
{
   int handle = iRSI(_Symbol, tf, MathMax(2, period), PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 50.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   int copied = CopyBuffer(handle, 0, shift, 1, buf);
   IndicatorRelease(handle);
   return (copied == 1) ? buf[0] : 50.0;
}

//+------------------------------------------------------------------+
//| V8.10 - Optimizer fitness (from ASQ): profit per unit drawdown,   |
//| boosted by win rate, profit factor, Sharpe, and recovery.         |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double trades = TesterStatistics(STAT_TRADES);
   double max_dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
   double recovery = TesterStatistics(STAT_RECOVERY_FACTOR);
   double wr = (trades > 0) ? TesterStatistics(STAT_PROFIT_TRADES) / trades * 100.0 : 0.0;
   double dd_cap = (InpMaxDrawdownLockPct > 0.0) ? InpMaxDrawdownLockPct : 20.0;
   if(trades < 30 || profit <= 0.0 || max_dd > dd_cap || wr < 40.0 || pf < 1.2)
      return 0.0;
   double fit = profit / MathMax(max_dd, 0.1);
   if(wr > 50.0) fit *= (1.0 + (wr - 50.0) / 100.0);
   if(pf > 1.5) fit *= (1.0 + (pf - 1.5) / 10.0);
   if(sharpe > 0.0) fit *= (1.0 + sharpe / 10.0);
   if(recovery > 1.0) fit *= (1.0 + MathMin(recovery, 5.0) / 10.0);
   return fit;
}
//+------------------------------------------------------------------+
