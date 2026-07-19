//+------------------------------------------------------------------+
//| SmartCoreEngine V6.37 - Fractal SR + Trendline + FVG Edition     |
//| Strategies: independent Fractal SR, Trendline and FVG setups     |
//| V6.10: pilot first trade, second-retest entries, SR level        |
//|        invalidation, per-tick profit giveback guard, sizing      |
//|        safety caps, and per-symbol journal/learning isolation    |
//| V6.20: anchored+locked dealing range with OTE zone, NFP news     |
//|        filter, SR touch-decay + H4 confluence scoring, regime-   |
//|        aware learning and routing, confirmation add-on trades,   |
//|        BOS-retest entries, H1 trendline touch and break-retest   |
//| V6.21: premium/discount range built on M15 to align with the SR  |
//|        lines, entries evaluated on the M2-M5 timeframe, and      |
//|        broker stop-level/freeze/spread padding on all stops      |
//| V6.30: Range Cycle strategy (buy clustered support, sell         |
//|        clustered resistance, exit at 90% of the range), equal-   |
//|        high/equal-low cluster boundary recognition and drawing,  |
//|        add-on spacing so pyramids never stack at one price, and  |
//|        second-retest + approach-speed rules on the losing setups |
//| V6.31: qualified premium/discount ROTATION trades - sell a       |
//|        proven multi-touch boundary rejection in premium (buy the |
//|        mirror in discount) even against the H1 trend, at reduced |
//|        risk, riding to 90% of the way to the opposite support/   |
//|        resistance. M15 structure must not oppose the rotation.   |
//| V6.32: earlier entries - boundaries prove with 2 touches and the  |
//|        next rejection trades; giveback guard loosened (1.25R arm, |
//|        60% tolerance) so winners breathe through normal pullbacks |
//| V6.33: M30 ORDER BLOCK confluence (SMC) - the last opposing      |
//|        candle before displacement, unmitigated, overlapping a    |
//|        proven SR zone. First return trades it standalone and     |
//|        every other aligned signal at the block earns a bonus.    |
//| V6.34: resting LIMIT ORDERS at confluent order blocks - the      |
//|        return into the block is captured even when it happens    |
//|        later; TP sits at a real historical level and staged       |
//|        extensions plus the giveback guard manage the fill.        |
//| V6.35: room to breathe - every stop honors a 1.5 M15-ATR floor,  |
//|        buffers widened, TP baseline fixed at DOUBLE the stop     |
//|        (extending on momentum via the staged ladder), break-even |
//|        at 1R, and the time exit relaxed for slower runners.       |
//| V6.36: FIX - the stop cap now measures on M15 like the floor, so |
//|        confirmed entries stop being rejected; resting OB limits  |
//|        honor the cap and default OFF (0/4 unconfirmed fills);    |
//|        trendline touches default OFF per their lifetime record.   |
//| V6.37: learning reset - a fresh journal file so the memory       |
//|        judges only the CURRENT logic, not old versions' sins;    |
//|        the regime bench needs 10 samples before zeroing anything |
//|              Built for MT5 Synthetic Indices                     |
//+------------------------------------------------------------------+
#property copyright "SmartCoreEngine V6.37"
#property version   "6.37"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

#define STRATEGY_COUNT 3
#define STRAT_SR       0
#define STRAT_TREND    1
#define STRAT_FVG      2

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "01 - Core Trading"
input long             InpMagicNumber                 = 312003;
input bool             InpAllowNewTrades              = true;
input bool             InpOneTradePerEntryBar         = true;
input int              InpMaxPositionsPerSymbol       = 1;
input int              InpMaxSpreadPoints             = 0;       // 0 disables spread filter
input int              InpMaxSlippagePoints           = 30;
input double           InpMinimumSignalScore          = 70.0;
input double           InpConfluenceBonus             = 12.0;
input int              InpMinAgreeingStrategies       = 1;      // retained for old set files; V6 chooses the best setup independently
input double           InpMinimumScoreGap             = 6.0;    // skip when opposing setups are too close to call
input bool             InpUseBoomCrashDirectionFilter = true;

input group "02 - Risk And Daily Limits"
input bool             InpUseFixedLot                 = false;
input double           InpFixedLot                    = 0.10;
input double           InpRiskPercent                 = 1.00;    // dynamic risk per trade
input double           InpMaxRiskPercent              = 2.00;    // hard safety cap
input double           InpMinRiskReward               = 2.00;
input double           InpDefaultRiskReward           = 2.00;    // baseline TP is DOUBLE the stop; momentum extends it further
input int              InpStopLossBufferPoints        = 20;
input bool             InpUseATRStopBuffer            = true;
input double           InpATRStopMultiplier           = 0.75;
input double           InpMinStopDistanceATR          = 1.50;    // no stop may sit closer than this many M15 ATRs from entry
input double           InpMaxDrawdownPercent          = 20.0;
input bool             InpUseVolatilityWeightedRisk   = true;
input int              InpVolatilityATRAvgBars        = 80;
input double           InpVolatilityRiskMinFactor     = 0.35;
input int              InpMaxSLPoints                 = 0;       // 0 disables
input double           InpMaxSLPercent                = 2.0;     // 0 disables
input bool             InpCapSLToATR                  = true;
input double           InpMaxSLATRMultiplier          = 2.5;
input bool             InpSkipTradeWhenSLTooWide      = true;
input bool             InpSkipTradeWhenMinLotTooRisky = true;
input group "02a - XAUUSD Wide-Stop Risk Profile"
input bool             InpUseXAUUSDRiskProfile        = true;
input string           InpXAUUSDSymbolKey             = "XAU";
input double           InpXAUUSDRiskPercent           = 0.25;   // 0.20-0.30% of equity per qualifying XAUUSD trade
input double           InpXAUUSDMaxRiskPercent        = 0.30;   // non-negotiable cap for the XAUUSD profile
input double           InpXAUUSDMaxSLPercent          = 5.00;   // wider price-distance allowance for gold's normal volatility
input double           InpXAUUSDMaxSLATRMultiplier    = 6.00;   // structural stop may be up to six M5 ATRs before rejection
input group "02b - Minimum-Lot Compatibility"
input bool             InpAllowMinimumLotCompatibility = true;  // allows the broker minimum when dynamic volume is too small
input double           InpMinimumLotMaxActualRiskPercent = 2.00; // hard actual-equity risk cap for a non-XAU minimum-lot entry
input double           InpXAUUSDMinimumLotMaxActualRiskPercent = 0.30; // gold keeps the 0.20-0.30% actual-risk limit
input group "02d - Pilot First Trade And Sizing Safety"
input bool             InpUsePilotFirstTrade          = true;    // first trade of a fresh trend uses the broker minimum lot
input double           InpPilotMaxActualRiskPercent   = 5.0;     // the pilot trade may never risk more than this % of equity
input double           InpPilotConfirmProfitRR        = 0.75;    // open pilot profit (in R) that confirms the trend
input int              InpPilotConfirmTimeoutBars     = 48;      // M15 bars before an idle unconfirmed pilot state resets
input double           InpMaxLotAbsolute              = 5.0;     // hard ceiling for any single position volume (0 disables)
input double           InpMaxRiskOverrunFactor        = 1.10;    // sized risk may never exceed the budget by more than this
input group "02e - Confirmation Add-On Positions (V6.20)"
input int              InpMaxConfirmationAddOns       = 2;       // extra positions allowed once the pilot confirms the trend (0-2)
input bool             InpAddOnOnlyWhenInProfit       = true;    // never average down: add only while every open trade is in profit
input double           InpAddOnRiskFactor             = 0.75;    // add-on trades use this fraction of the normal risk budget
input double           InpAddOnMinSpacingATR          = 0.50;    // an add-on needs this much favorable movement since the last entry
input double           InpDailyProfitTargetMoney      = 0.0;     // 0 disables
input double           InpDailyLossLimitMoney         = 0.0;     // 0 disables
input double           InpDailyProfitTargetPercent    = 0.0;     // 0 disables
input double           InpDailyLossLimitPercent       = 0.0;     // 0 disables
input bool             InpDailyLimitsUseFloatingPL    = true;
input bool             InpClosePositionsAtDailyLimit  = true;

input group "03 - Journal Memory"
input bool             InpUseTradingJournal           = true;
input bool             InpUseJournalLearning          = true;
input string           InpJournalFileName             = "ndlovujournal_v637.csv";
input int              InpLearningMinTrades           = 8;
input double           InpLearningMaxBoostPercent     = 18.0;
input double           InpLearningMaxPenaltyPercent   = 14.0;

input group "03b - Regime-Aware Learning And Routing (V6.20)"
input bool             InpUseRegimeLearning           = true;    // learn win rates per strategy PER market regime
input int              InpRegimeLearningMinTrades     = 10;      // the bench needs this many samples per strategy-per-regime before acting
input double           InpRegimeMaxBoostPercent       = 20.0;
input double           InpRegimeMaxPenaltyPercent     = 20.0;
input bool             InpBenchLosingStrategies       = true;    // bench a strategy in a regime where it keeps losing
input double           InpBenchWinRateThreshold       = 40.0;    // bench below this win % (with enough samples and net loss)
input bool             InpUseRegimePriors             = true;    // sensible hard-coded routing before data accumulates
input double           InpRegimeExpansionATRFactor    = 1.50;    // current ATR above average by this factor = volatile expansion

input group "04 - Timeframes"
input ENUM_TIMEFRAMES  InpStructureTF                 = PERIOD_M15;
input ENUM_TIMEFRAMES  InpEntryTF                     = PERIOD_M3;   // entry/confirmation timeframe; M2-M5 recommended
input ENUM_TIMEFRAMES  InpTrendHigherTF1              = PERIOD_H1;
input ENUM_TIMEFRAMES  InpTrendHigherTF2              = PERIOD_M15;
input ENUM_TIMEFRAMES  InpTrendExecutionTF            = PERIOD_M15;
input int              InpM15HistoricalLookback       = 1000;   // always clamped to at least 1,000 M15 candles for TP targets

input group "05 - Premium, Discount And Equilibrium Filter"
input bool             InpUsePremiumDiscountFilter    = true;
input int              InpFractalDepth                = 2;      // confirmed five-candle fractals
input double           InpEquilibriumBandPercent      = 2.0;    // neutral no-trade band as a % of the dealing range
input double           InpEquilibriumRetestATR        = 0.15;   // retest tolerance on M5
input int              InpEquilibriumBreakoutLookback = 18;     // recent M5 bars searched for a confirmed break
input bool             InpAllowRangeReversalEntries   = true;   // allows confirmed reversal trades while H1 is ranging
input int              InpRangeReversalLookbackBars   = 48;     // M15 bars searched for rejection and CHoCH
input double           InpRangeReversalScoreBonus     = 20.0;
input bool             InpEnableOuterRangeBreakouts   = true;   // premium-high / discount-low breakout continuation
input double           InpOuterRangeBreakoutATR       = 0.15;   // M15 close must exceed range edge by this ATR fraction
input bool             InpOuterRangeRequiresM5Confirm = true;
input bool             InpUseFreshTrendRecognition    = true;   // recognise a new confirmed CHoCH/BOS before all fractals have formed
input int              InpFreshTrendLookbackBars      = 32;     // most recent M15/H1 bars eligible for a fresh-trend override
input double           InpFreshTrendImpulseATR        = 0.50;   // the structural break needs an impulsive candle of at least this ATR size
input double           InpFreshTrendMinBodyRatio      = 0.55;   // prevents a wick-only break from changing the trend state

input group "05b - Second Retest Entry Rule"
input bool             InpRequireSecondRetest         = true;    // SR and channel entries wait for the second distinct retest
input int              InpRetestLookbackBars          = 96;      // M15 bars searched when counting distinct retests
input int              InpRetestSeparationBars        = 3;       // bars needed between touches to count as separate retests
input int              InpSRInvalidationCloses        = 2;       // consecutive closes beyond a level retire it as intact SR

input group "05c - Anchored Dealing Range And OTE (V6.20)"
input bool             InpUseAnchoredDealingRange     = true;    // anchor the range to the impulse leg that broke structure
input ENUM_TIMEFRAMES  InpDealingRangeTF              = PERIOD_M15; // premium/discount range timeframe (aligned with the M15 SR lines)
input double           InpMinRangeWidthATR            = 6.0;     // minimum range width in dealing-range TF ATRs (6 M15 ATRs = about 3 H1 ATRs)
input bool             InpLockRangeUntilBreak         = true;    // keep the range stable until price closes beyond it
input bool             InpUseOTEZone                  = true;    // bonus for entries inside the 62-79% retracement pocket
input double           InpOTEStart                    = 0.62;
input double           InpOTEEnd                      = 0.79;
input double           InpOTEScoreBonus               = 6.0;

input group "05d - News Filter, NFP (V6.20)"
input bool             InpUseNewsFilter               = true;
input int              InpNewsMode                    = 0;       // 0 = skip news, 1 = trade at reduced risk, 2 = exploit post-news displacement
input bool             InpNewsOnlyRealMarkets         = true;    // synthetic indices ignore economic news entirely
input int              InpNewsHourServer              = 15;      // NFP release hour in YOUR BROKER SERVER time (verify against 8:30 New York!)
input int              InpNewsMinuteServer            = 30;
input int              InpNewsBlockBeforeMin          = 30;      // no new entries this many minutes before the release
input int              InpNewsBlockAfterMin           = 30;      // and this many minutes after it
input double           InpNewsReduceRiskFactor        = 0.25;    // risk fraction used in REDUCE mode and in the exploit window
input int              InpNewsExploitWindowMin        = 90;      // exploit window length after the blackout ends
input double           InpNewsDisplacementATR         = 2.0;     // the news spike candle must exceed this many average M5 ATRs
input int              InpNewsMaxSpreadPoints         = 0;       // extra spread cap during any news window (0 = use the normal filter)

input group "06 - FVG Retest Strategy"
input bool             InpEnableFVGRetest             = true;
input int              InpStructureSwingDepth         = 2;      // confirmed five-candle fractal used by SR, structure, and FVG checks
input int              InpFVGMinGapPoints             = 50;
input int              InpFVGLookbackBars             = 120;    // M15 bars searched for fresh FVGs
input int              InpFVGMaxAgeBars               = 48;     // do not trade stale FVGs
input double           InpFVGMinDisplacementATR       = 0.75;   // middle displacement candle must be meaningful
input double           InpFVGMinRetestPercent         = 15.0;   // price must enter at least this far into the gap
input bool             InpFVGRequireBreakOfStructure  = true;   // a linked M15 BOS/CHoCH must precede the FVG retest entry
input int              InpFVGBOSLookbackBars          = 12;     // BOS/CHoCH may occur shortly before or during FVG creation
input bool             InpFVGRequireM15Structure      = true;   // M15 trend alignment or a confirmed M15 CHoCH is required
input bool             InpFVGRequireM5Confirmation    = true;   // rejection/continuation candle after the retest is required
input bool             InpAllowEliteWideStop          = true;   // available to any exceptional V6 setup
input double           InpEliteScoreForWideStop       = 85.0;   // score needed for the exceptional wide-stop allowance
input double           InpEliteMaxSLMultiplier        = 2.00;   // still rejects extreme stops above this multiple of the normal cap

input group "06b - M30 Order Block Confluence (V6.33)"
input bool             InpEnableOBConfluence          = true;    // trade M30 order blocks that overlap a proven SR zone
input ENUM_TIMEFRAMES  InpOrderBlockTF                = PERIOD_M30;
input int              InpOBLookbackBars              = 240;     // order-block TF bars searched for fresh blocks
input int              InpOBMaxAgeBars                = 96;      // a block older than this (in OB-TF bars) is stale
input double           InpOBMinDisplacementATR        = 1.0;     // the impulse leaving the block must span this many OB-TF ATRs
input double           InpOBConfluenceScore           = 80.0;    // standalone OB + SR confluence signal score
input double           InpOBConfluenceBonus           = 6.0;     // score bonus for other aligned signals sitting at the block
input bool             InpShowM30OrderBlocks          = true;
input bool             InpUseOBLimitOrders            = false;   // OFF by default: touch-fills went 0/4; the confirmed OB market entry stays on
input double           InpOBLimitEntryLevel           = 50.0;    // entry depth into the block: 0 = near edge, 50 = midpoint, 100 = far edge
input int              InpOBLimitExpiryBars           = 48;      // pending expires after this many OB-TF bars (0 = lives while the block is valid)

input group "07 - SRBounce Strategy"
input bool             InpEnableSRBounce              = true;
input bool             InpSR_EnableBounce             = true;
input bool             InpSR_EnablePullbackRetest     = true;
input bool             InpSR_EnableDirectBreakout     = true;
input bool             InpSR_EnableFalseBreakoutTrap  = true;
input bool             InpSR_EnableChannelTrading     = true;
input bool             InpSR_EnableFirstyMethod       = true;
input int              InpSRLookbackBars              = 160;
input int              InpSRZoneTolerancePoints       = 1500;
input bool             InpSRUseATRZone                = true;
input double           InpSRATRZoneMultiplier         = 0.20;
input double           InpSRDisplayZoneMultiplier     = 0.35;
input bool             InpSRSnapLineToWickCluster     = true;
input int              InpSRMinTouches                = 2;
input int              InpSRRSIPeriod                 = 14;
input int              InpSRManualSLPoints            = 5000;
input bool             InpSRUseNextZoneForTP          = true;
input double           InpSRBreakoutThresholdATR      = 0.15;
input int              InpSRBreakoutConfirmBars       = 1;
input bool             InpRequireConfirmedSREntry     = true;   // every trade must obey the confirmed support/resistance rule
input bool             InpSRRoleReversalRequireM5     = true;   // broken level must hold on an M5 retest before reversal entry

input group "07b - SR Level Quality (V6.20)"
input int              InpSRTouchDecayAfter           = 4;       // touches beyond this weaken a level (its liquidity is being eaten)
input double           InpSRTouchDecayPenalty         = 6.0;     // score penalty per touch beyond the decay point
input bool             InpRequireHTFConfluence        = false;   // hard-block M15 levels with no H4 level behind them
input double           InpHTFConfluenceATR            = 0.50;    // an H4 fractal within this many H4 ATRs counts as confluence
input double           InpHTFConfluenceBonus          = 8.0;
input double           InpHTFMissingPenalty           = 10.0;
input bool             InpUseApproachSpeedFilter      = true;    // slow grinds into a level tend to break it, not bounce
input int              InpApproachBars                = 4;
input double           InpSlowGrindMaxATRPerBar       = 0.35;    // average approach bar below this many ATRs = slow grind

input group "07c - Range Cycle Strategy (V6.30)"
input bool             InpEnableRangeCycle            = true;    // buy clustered support / sell clustered resistance in ranging markets
input int              InpClusterMinTouches           = 2;       // swing highs (or lows) within tolerance needed to form a boundary
input double           InpClusterTolATR               = 0.30;    // cluster width in M15 ATRs (how tightly the peaks must line up)
input double           InpRangeMinHeightATR           = 2.0;     // minimum range height in M15 ATRs
input double           InpRangeExitPercent            = 90.0;    // exit at this % of the way to the opposite boundary
input double           InpRangeMinRR                  = 2.00;    // a range trade must offer at least double the stop to the boundary
input double           InpRangeCycleScore             = 77.0;
input bool             InpRangeCycleOnlyWhenRanging   = true;    // trade the cycle only while the market regime is Ranging

input group "07d - Premium/Discount Rotation (V6.31)"
input bool             InpEnableRotationTrades        = true;    // sell proven premium rejections / buy proven discount rejections
input int              InpRotationMinTouches          = 2;       // the rejected boundary needs at least this many touches
input double           InpRotationExitPercent         = 90.0;    // ride to this % of the way to the opposite boundary
input double           InpRotationMinRR               = 2.00;    // a rotation must offer at least double the stop to its target
input double           InpRotationScore               = 79.0;
input double           InpRotationRiskFactor          = 0.75;    // rotation trades risk this fraction of the normal budget
input bool             InpRotationBlockVsM15Trend     = true;    // skip when M15 structure still runs against the rotation

input group "07 - Supply And Demand Confluence"
input bool             InpEnableSupplyDemandZones     = false;  // disabled by default to keep the chart clean
input ENUM_TIMEFRAMES  InpSupplyDemandHTF             = PERIOD_H4;
input ENUM_TIMEFRAMES  InpSupplyDemandITF             = PERIOD_H1;
input ENUM_TIMEFRAMES  InpSupplyDemandLTF             = PERIOD_M15;
input int              InpSDLookbackBars              = 420;
input double           InpSDFuzzFactor                = 0.75;
input int              InpSDMinStrength               = 2;
input double           InpSDConfluenceBonus           = 12.0;
input double           InpSDNearZoneATR               = 0.25;
input int              InpCustomSRLookback            = 300;
input double           InpCustomSRTolerancePips       = 10.0;
input int              InpCustomSRMaxExtremes         = 20;
input bool             InpShowSupplyDemandZones       = false;  // disabled by default to keep the chart clean
input int              InpMaxVisibleSDZones           = 6;

input group "08 - TrendFollowing Strategy"
input bool             InpEnableTrendFollowing        = true;
input int              InpTrendSMAFast                = 8;
input int              InpTrendEMAFast                = 20;
input int              InpTrendEMA50                  = 50;
input int              InpTrendEMA200                 = 200;
input int              InpTrendMACDFast               = 12;
input int              InpTrendMACDSlow               = 26;
input int              InpTrendMACDSignal             = 9;
input int              InpTrendRSIPeriod              = 14;
input int              InpTrendATRPeriod              = 20;
input int              InpTrendTSMOMLookback          = 60;
input int              InpTrendSwingDepth             = 2;      // confirmed five-candle fractal
input int              InpTrendBreakConfirmCandles    = 3;
input bool             InpTrendRequireStrongBodies    = true;

input group "08b - H1 Trendline And BOS-Retest Trades (V6.20)"
input bool             InpEnableTrendlineTouch        = false;   // OFF by default per its lifetime journal record; re-enable to keep testing it
input bool             InpEnableTrendlineBreakRetest  = true;    // trade the break of a trendline after its retest holds
input bool             InpEnableBOSRetest             = true;    // trade the retest of a confirmed break of structure
input ENUM_TIMEFRAMES  InpTrendlineTF                 = PERIOD_H1;
input double           InpTrendlineTouchATR           = 0.25;    // touch tolerance in M15 ATRs
input int              InpTrendlineBreakCloses        = 2;       // closed M15 bars beyond the line to confirm a break
input double           InpTrendlineScore              = 76.0;
input int              InpTrendlineMinLineTouches     = 4;       // distinct line touches (anchors included) before a touch trade; 3 = first touch after the line forms
input double           InpBOSRetestScore              = 78.0;
input int              InpBOSRetestLookback           = 40;      // M15 bars searched for the structure break
input bool             InpSelfConfirmedBypassFilters  = true;    // TL/BOS/NFP setups carry their own confirmation instead of the horizontal SR gate

input group "09 - Adaptive Exits And Trailing"
input bool             InpUseAdaptiveExit             = true;
input bool             InpUseBreakEven                = true;
input double           InpBreakEvenAtRR               = 1.00;
input int              InpBreakEvenBufferPoints       = 5;
input double           InpBreakEvenATRBufferMultiplier = 0.15;
input bool             InpUseATRTrailingStop          = true;
input double           InpTrailStartRR                = 1.50;
input double           InpTrailATRMultiplier          = 2.25;
input double           InpTrailTightenStepATR         = 0.25;
input bool             InpUseStagedHistoricalTargets  = true;   // TP1 -> TP3 -> 2R runner; each passed level becomes protected SL
input double           InpTargetExtensionTriggerPercent = 90.0; // extend before broker TP is reached when momentum is strong
input double           InpTPRunnerExtensionRR         = 2.00;   // additional initial-risk distance beyond TP3 for the final runner
input bool             InpUseTrailingTakeProfit       = false;  // staged targets control TP progression by default
input double           InpTPExtendThresholdATR        = 0.55;
input double           InpTPExtendATRMultiplier       = 1.20;
input bool             InpUseMATrailingTP             = false;  // staged targets control TP progression by default
input int              InpMATPPeriod                  = 50;
input double           InpMATPATRMultiplier           = 1.50;
input bool             InpUsePartialTargets           = false;  // profits are protected by passed-target SLs instead of an early partial close
input double           InpPartialCloseAtRR            = 2.00;
input double           InpPartialClosePercent         = 50.0;
input bool             InpMoveSLToBEAfterPartial      = true;
input double           InpSoftExitMinimumRR           = 1.50;
input int              InpAdaptiveExitMinHoldBars     = 12;
input bool             InpExitOnMomentumFailure       = false;  // ordinary pullbacks should be managed by SL/trailing, not closed
input bool             InpAdaptiveExitRequiresStructureBreak = true;
input int              InpMaxTradeBars                = 160;
input bool             InpCloseOnOppositeSignal       = true;
input bool             InpManageStopsOnNewM15Bar      = true;  // prevents tick-by-tick trailing and lets valid trades breathe

input group "09b - Profit Giveback Guard"
input bool             InpUseProfitGivebackGuard      = true;
input double           InpGivebackArmRR               = 1.25;    // guard arms once this open R multiple has been reached
input double           InpMaxProfitGivebackPercent    = 60.0;    // close if this % of the peak open profit is given back
input double           InpProfitLockTriggerPercent    = 70.0;    // lock a stop floor at this % progress toward TP
input double           InpProfitLockKeepPercent       = 50.0;    // the floor keeps this % of the current open gain

input group "10 - Visuals"
input bool             InpDrawVisuals                 = true;
input bool             InpClearOldVisuals             = true;
input int              InpVisualLookbackBars          = 220;
input int              InpVisualExtendBars            = 12;
input int              InpStructureLabelOffsetBars    = 2;      // BOS/CHoCH labels stay close to the current price action
input bool             InpApplyCleanChartTheme        = true;
input bool             InpShowDashboard               = true;
input bool             InpShowSupportResistance       = true;
input bool             InpShowTrendLines              = true;
input bool             InpShowOrderBlocks             = false;  // legacy visual is disabled by default
input bool             InpShowFairValueGaps           = true;
input bool             InpShowPremiumDiscount         = true;
input bool             InpShowCHOCH                   = true;
input bool             InpShowHistoricalTPTargets     = true;
input int              InpMaxVisibleHistoricalTPTargets = 3;    // nearest prior swing highs and lows only
input bool             InpShowMajorSwingLevels        = true;   // M30, H1 and H4 prior major highs/lows
input int              InpMaxMajorSwingLevelsPerTF    = 1;      // one dominant high and low per timeframe keeps the chart clean
input int              InpMajorSwingDepth             = 5;      // ignores small fractals when deciding what is truly major
input int              InpMajorSwingBreakWindow       = 40;     // bars allowed for the swing to prove itself with a structure break
input double           InpMajorSwingMinImpulseATR     = 3.0;    // a major pivot must create a meaningful expansion, not a small retracement
input int              InpMaxVisibleFVG               = 4;
input int              InpMaxVisibleOB                = 3;
input int              InpDashboardX                  = 12;
input int              InpDashboardY                  = 18;
input int              InpDashboardRefreshSeconds     = 2;      // update labels without deleting/recreating them on every tick

//+------------------------------------------------------------------+
//| Structures                                                       |
//+------------------------------------------------------------------+
struct TradeSignal
{
   bool     valid;
   int      direction;       // 1 buy, -1 sell
   double   score;
   int      agreeing_strategies;
   string   strategy;
   string   setup;
   string   reason;
   double   sl;
   double   tp;
};

struct DealingRange
{
   bool     valid;
   double   low;
   double   high;
   double   equilibrium;
   double   equilibrium_band;
};

struct PriceZone
{
   bool     valid;
   int      direction;       // 1 demand/support, -1 supply/resistance
   double   low;
   double   high;
   int      touches;
   int      strength;
   bool     broken;
   bool     retested;
   ENUM_TIMEFRAMES timeframe;
   datetime start_time;
   datetime end_time;
   string   label;
};

struct MarketStructure
{
   int      trend;           // 1 bullish, -1 bearish, 0 neutral
   double   last_high;
   double   prev_high;
   double   last_low;
   double   prev_low;
   double   idm;
   double   dealing_high;
   double   dealing_low;
   bool     bullish_bos;
   bool     bearish_bos;
   bool     bullish_choch;
   bool     bearish_choch;
};

struct TrendLine
{
   bool     valid;
   datetime t1;
   datetime t2;
   double   p1;
   double   p2;
};

struct EntryDealInfo
{
   bool     found;
   string   strategy;
   int      direction;
   double   volume;
   double   open_price;
   double   sl;
   double   tp;
   datetime open_time;
};

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
string   g_strategy_names[STRATEGY_COUNT] = {"SRBounce", "TrendFollowing", "FVGRetest"};
int      g_strategy_trades[STRATEGY_COUNT];
int      g_strategy_wins[STRATEGY_COUNT];
int      g_strategy_losses[STRATEGY_COUNT];
double   g_strategy_profit[STRATEGY_COUNT];
string   g_strategy_best_setup[STRATEGY_COUNT];
double   g_strategy_best_setup_profit[STRATEGY_COUNT];

#define MAX_SD_ZONES 24
#define ZONE_WEAK      0
#define ZONE_TURNCOAT  1
#define ZONE_UNTESTED  2
#define ZONE_VERIFIED  3
#define ZONE_PROVEN    4

PriceZone g_sd_zones[MAX_SD_ZONES];
int       g_sd_zone_count = 0;
double    g_custom_res_levels[2];
double    g_custom_sup_levels[2];
datetime  g_last_sd_scan_time = 0;

datetime g_last_entry_bar_time = 0;
datetime g_last_trade_bar_time = 0;
datetime g_last_visual_bar_time = 0;
datetime g_last_management_bar_time = 0;
datetime g_last_dashboard_refresh_time = 0;
datetime g_day_start_time = 0;
double   g_day_start_equity = 0.0;
bool     g_daily_locked = false;
string   g_daily_lock_reason = "";
string   g_last_risk_reject_reason = "";
double   g_last_risk_cash = 0.0;
double   g_last_loss_per_lot = 0.0;
double   g_last_volatility_risk_factor = 1.0;
bool     g_last_minimum_lot_compatibility_used = false;
bool     g_last_pilot_lot_used = false;
bool     g_rotation_sizing = false;
string   g_last_dashboard_signal = "Waiting for a confirmed setup";
string   g_last_value_filter_reason = "";
int      g_last_tp_visual_direction = 0;

// V6.20 regime-aware learning memory
#define REGIME_COUNT 4
// regime index: 0 unknown, 1 trending, 2 ranging, 3 volatile expansion
int      g_regime_trades[STRATEGY_COUNT][REGIME_COUNT];
int      g_regime_wins[STRATEGY_COUNT][REGIME_COUNT];
double   g_regime_profit[STRATEGY_COUNT][REGIME_COUNT];
int      g_current_regime = 0;
datetime g_last_regime_bar = 0;

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippagePoints);

   ResetStrategyMemory();
   SetupDailyState();
   RefreshSupplyDemandZones();
   EnsureJournalHeader();
   LoadJournalMemory();

   if(InpApplyCleanChartTheme)
      ApplyCleanChartTheme();

   if(InpDrawVisuals)
      RefreshVisuals();
   RefreshDashboardIfNeeded(true);

   if(InpEntryTF > PERIOD_M5)
      Print("Warning: InpEntryTF is above M5. Entries were designed for the M2-M5 range.");
   Print("SmartCoreEngine V6.37 initialized. Clean learning slate: memory now judges only the current logic, bench needs 10 samples.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpClearOldVisuals)
      DeleteObjectsByPrefix("SCE312_");
}

void OnTick()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippagePoints);

   ResetDailyStateIfNeeded();
   CheckDailyLimits();
   // This performs only one-off TP-stage extensions and protective stop moves.
   // It is intentionally separate from the slower M15 trailing/exit manager.
   ManageStagedHistoricalTargets();
   // V6.10: winners are protected on every tick, not only on a new M15 bar.
   GuardOpenProfits();
   if(!InpManageStopsOnNewM15Bar || IsNewBar(InpTrendExecutionTF, g_last_management_bar_time))
      ManageOpenPositions();
   if(InpDrawVisuals)
      SyncHistoricalTPVisuals();
   RefreshDashboardIfNeeded(false);

   if(g_daily_locked)
      return;

   if(!InpAllowNewTrades)
      return;

   if(!IsNewBar(InpEntryTF, g_last_entry_bar_time))
      return;

   // V6.10: once per M5 bar, keep the pilot/full sizing state in sync
   // with the H1 trend. A fresh trend always starts with a pilot trade.
   UpdatePilotTrendState();

   // V6.34: keep the resting order-block limit orders in sync with the
   // live blocks - place, replace, or cancel them as the blocks evolve.
   ManageOrderBlockLimitOrders();

   if(IsNewBar(InpStructureTF, g_last_visual_bar_time))
   {
      RefreshSupplyDemandZones();
      if(InpDrawVisuals)
         RefreshVisuals();
   }

   if(InpOneTradePerEntryBar && g_last_trade_bar_time == g_last_entry_bar_time)
      return;

   if(!TradingEnvironmentOK())
      return;

   // V6.20: after the pilot confirms the trend, up to InpMaxConfirmationAddOns
   // additional positions may be opened - but never while any open trade is losing.
   int our_positions = CountOurPositions(_Symbol);
   if(our_positions >= EffectiveMaxPositions())
      return;
   if(our_positions > 0 && InpAddOnOnlyWhenInProfit && AnyOurPositionInLoss())
      return;

   // ---- V6.20 news filter (NFP) --------------------------------------
   int news_state = NewsStateNow();
   if(news_state == 1 && InpNewsMode != 1)
   {
      g_last_dashboard_signal = "News blackout (NFP): no new entries";
      return;
   }
   if(news_state != 0 && InpNewsMaxSpreadPoints > 0)
   {
      double news_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double news_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if((int)MathRound((news_ask - news_bid) / _Point) > InpNewsMaxSpreadPoints)
      {
         g_last_dashboard_signal = "News window: spread above the news spread cap";
         return;
      }
   }
   if(news_state == 2)
   {
      // Exploit window: the initial spike is untradeable; the retest of the
      // spike's FVG is the edge. Ordinary setups stay off until this ends.
      TradeSignal news_signal;
      if(BuildNewsDisplacementSignal(news_signal) &&
         news_signal.score >= InpMinimumSignalScore &&
         DirectionAllowedForSymbol(news_signal.direction))
      {
         if(OpenSignal(news_signal))
            g_last_trade_bar_time = g_last_entry_bar_time;
      }
      else
         g_last_dashboard_signal = "NFP exploit window: waiting for displacement FVG retest";
      return;
   }

   TradeSignal signal;
   BuildCombinedSignal(signal);
   if(signal.valid && signal.score >= InpMinimumSignalScore && DirectionAllowedForSymbol(signal.direction))
   {
      // V6.30: add-ons must be same-direction and spaced by favorable
      // movement, so pyramids can never stack three entries at one price.
      if(our_positions > 0 && !AddOnConditionsMet(signal.direction))
         return;
      if(OpenSignal(signal))
         g_last_trade_bar_time = g_last_entry_bar_time;
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!InpUseTradingJournal)
      return;

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal))
      return;

   long magic = (long)HistoryDealGetInteger(deal, DEAL_MAGIC);
   if(magic != InpMagicNumber)
      return;

   // V6.10: every chart instance receives every deal event. Only the
   // chart whose symbol matches the deal may journal and learn from it.
   // This fixes the duplicate and cross-symbol rows found in the journal.
   string deal_symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
   if(deal_symbol != _Symbol)
      return;

   long entry_type = HistoryDealGetInteger(deal, DEAL_ENTRY);

   // V6.34: a resting order-block limit has filled. Store the true risk so
   // staged targets and the giveback guard manage it exactly like a market
   // entry, and journal the fill.
   if(entry_type == DEAL_ENTRY_IN)
   {
      long fill_type = HistoryDealGetInteger(deal, DEAL_TYPE);
      int fill_direction = (fill_type == DEAL_TYPE_BUY) ? 1 : -1;
      string order_key = OBOrderTicketKey(fill_direction);
      if(GlobalVariableCheck(order_key))
      {
         double fill_price = HistoryDealGetDouble(deal, DEAL_PRICE);
         double fill_sl = HistoryDealGetDouble(deal, DEAL_SL);
         ulong fill_position = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(fill_sl > 0.0 && fill_position > 0)
            GlobalVariableSet(PositionRiskKey(fill_position), MathAbs(fill_price - fill_sl));
         LogJournal("OPEN", deal, deal_symbol, DirectionToText(fill_direction),
                    HistoryDealGetDouble(deal, DEAL_VOLUME), fill_price, 0.0,
                    fill_sl, HistoryDealGetDouble(deal, DEAL_TP),
                    "FVGRetest", "OPEN", 0.0, "Order-block limit order filled",
                    "Price returned into the M30 order block and the resting entry executed",
                    "Staged targets, giveback guard, and profit locks now manage the trade",
                    (fill_direction == 1) ? "OB_SR_Limit_Buy" : "OB_SR_Limit_Sell");
         GlobalVariableDel(order_key);
         GlobalVariableDel(OBOrderTimeKey(fill_direction));
      }
      return;
   }

   if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_OUT_BY && entry_type != DEAL_ENTRY_INOUT)
      return;

   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(deal, DEAL_SWAP)
                 + HistoryDealGetDouble(deal, DEAL_COMMISSION);

   ulong position_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   EntryDealInfo entry = FindEntryDeal(position_id);
   string strategy = entry.strategy;
   if(strategy == "")
      strategy = ExpandStrategyFromComment(HistoryDealGetString(deal, DEAL_COMMENT));

   int direction = entry.direction;
   if(direction == 0)
   {
      long deal_type = HistoryDealGetInteger(deal, DEAL_TYPE);
      direction = (deal_type == DEAL_TYPE_SELL) ? 1 : -1;
   }

   // V6.10 pilot logic: a winning pilot confirms the trend and unlocks
   // full risk-based sizing; a losing pilot means the next trade of this
   // trend is a minimum-lot pilot again.
   if(InpUsePilotFirstTrade && PilotStage() == 1)
      SetPilotStage(profit > 0.0 ? 2 : 0);

   string result_text = "BREAKEVEN";
   if(profit > 0.0)
      result_text = "WIN";
   else if(profit < 0.0)
      result_text = "LOSS";

   double close_price = HistoryDealGetDouble(deal, DEAL_PRICE);
   double lot = HistoryDealGetDouble(deal, DEAL_VOLUME);
   double open_price = entry.open_price;
   double sl = entry.sl;
   double tp = entry.tp;
   string direction_text = DirectionToText(direction);
   string close_reason = CloseReasonText((long)HistoryDealGetInteger(deal, DEAL_REASON), profit);
   string explanation = BuildWinLossExplanation(strategy, direction, profit, close_reason);
   string adjustment = BuildAdjustmentText(strategy, profit);
   string best_setup = MemorySummary();

   LogJournal("CLOSE", deal, deal_symbol, direction_text, lot, open_price, close_price, sl, tp,
              strategy, result_text, profit, close_reason, explanation, adjustment, best_setup);

   UpdateStrategyMemory(strategy, profit, best_setup);
}

//+------------------------------------------------------------------+
//| Signal aggregation (all now using reference parameters)         |
//+------------------------------------------------------------------+
void BuildCombinedSignal(TradeSignal &out)
{
   TradeSignal empty;
   EmptySignal(empty);
   TradeSignal sr;
   TradeSignal trend;
   TradeSignal fvg_buy;
   TradeSignal fvg_sell;
   TradeSignal range_buy;
   TradeSignal range_sell;
   TradeSignal outer_buy;
   TradeSignal outer_sell;
   EmptySignal(sr);
   EmptySignal(trend);
   EmptySignal(fvg_buy);
   EmptySignal(fvg_sell);
   EmptySignal(range_buy);
   EmptySignal(range_sell);
   EmptySignal(outer_buy);
   EmptySignal(outer_sell);

   if(InpEnableSRBounce)
      EvaluateSRBounceSignal(sr);
   if(InpEnableTrendFollowing)
      EvaluateTrendFollowingSignal(trend);
   if(InpEnableFVGRetest)
   {
      BuildFVGRetestSignal(1, fvg_buy);
      BuildFVGRetestSignal(-1, fvg_sell);
   }
   if(InpAllowRangeReversalEntries)
   {
      BuildRangeReversalSignal(1, range_buy);
      BuildRangeReversalSignal(-1, range_sell);
   }
   if(InpEnableOuterRangeBreakouts)
   {
      BuildOuterRangeBreakoutSignal(1, outer_buy);
      BuildOuterRangeBreakoutSignal(-1, outer_sell);
   }

   // V6.20: H1 trendline touch, trendline break-and-retest, and BOS-retest
   TradeSignal tl_touch_buy, tl_touch_sell, tl_break_buy, tl_break_sell, bos_buy, bos_sell;
   EmptySignal(tl_touch_buy);
   EmptySignal(tl_touch_sell);
   EmptySignal(tl_break_buy);
   EmptySignal(tl_break_sell);
   EmptySignal(bos_buy);
   EmptySignal(bos_sell);
   if(InpEnableTrendlineTouch)
   {
      BuildTrendlineTouchSignal(1, tl_touch_buy);
      BuildTrendlineTouchSignal(-1, tl_touch_sell);
   }
   if(InpEnableTrendlineBreakRetest)
   {
      BuildTrendlineBreakRetestSignal(1, tl_break_buy);
      BuildTrendlineBreakRetestSignal(-1, tl_break_sell);
   }
   if(InpEnableBOSRetest)
   {
      BuildBOSRetestSignal(1, bos_buy);
      BuildBOSRetestSignal(-1, bos_sell);
   }

   // V6.30: Range Cycle - trade the oscillation between clustered boundaries
   TradeSignal cycle_buy, cycle_sell;
   EmptySignal(cycle_buy);
   EmptySignal(cycle_sell);
   if(InpEnableRangeCycle)
   {
      BuildRangeCycleSignal(1, cycle_buy);
      BuildRangeCycleSignal(-1, cycle_sell);
   }

   // V6.31: qualified premium/discount rotation trades
   TradeSignal rot_buy, rot_sell;
   EmptySignal(rot_buy);
   EmptySignal(rot_sell);
   if(InpEnableRotationTrades)
   {
      BuildRotationSignal(1, rot_buy);
      BuildRotationSignal(-1, rot_sell);
   }

   // V6.33: M30 order blocks confluent with SR zones
   TradeSignal ob_buy, ob_sell;
   EmptySignal(ob_buy);
   EmptySignal(ob_sell);
   if(InpEnableOBConfluence)
   {
      BuildOBConfluenceSignal(1, ob_buy);
      BuildOBConfluenceSignal(-1, ob_sell);
   }

   TradeSignal best_buy, best_sell;
   EmptySignal(best_buy);
   EmptySignal(best_sell);

   SelectBestIndependentSignal(sr, best_buy, best_sell);
   SelectBestIndependentSignal(trend, best_buy, best_sell);
   SelectBestIndependentSignal(fvg_buy, best_buy, best_sell);
   SelectBestIndependentSignal(fvg_sell, best_buy, best_sell);
   SelectBestIndependentSignal(range_buy, best_buy, best_sell);
   SelectBestIndependentSignal(range_sell, best_buy, best_sell);
   SelectBestIndependentSignal(outer_buy, best_buy, best_sell);
   SelectBestIndependentSignal(outer_sell, best_buy, best_sell);
   SelectBestIndependentSignal(tl_touch_buy, best_buy, best_sell);
   SelectBestIndependentSignal(tl_touch_sell, best_buy, best_sell);
   SelectBestIndependentSignal(tl_break_buy, best_buy, best_sell);
   SelectBestIndependentSignal(tl_break_sell, best_buy, best_sell);
   SelectBestIndependentSignal(bos_buy, best_buy, best_sell);
   SelectBestIndependentSignal(bos_sell, best_buy, best_sell);
   SelectBestIndependentSignal(cycle_buy, best_buy, best_sell);
   SelectBestIndependentSignal(cycle_sell, best_buy, best_sell);
   SelectBestIndependentSignal(rot_buy, best_buy, best_sell);
   SelectBestIndependentSignal(rot_sell, best_buy, best_sell);
   SelectBestIndependentSignal(ob_buy, best_buy, best_sell);
   SelectBestIndependentSignal(ob_sell, best_buy, best_sell);

   if(!best_buy.valid && !best_sell.valid)
   {
      out = empty;
      g_last_dashboard_signal = (g_last_value_filter_reason == "") ?
                                "No valid SR, trend, or FVG setup" : g_last_value_filter_reason;
      return;
   }

   if(best_buy.valid && best_sell.valid)
   {
      if(MathAbs(best_buy.score - best_sell.score) < MathMax(0.0, InpMinimumScoreGap))
      {
         // Do not countertrade ourselves when the market provides equally plausible directions.
         out = empty;
         g_last_dashboard_signal = "Conflicting buy and sell signals";
         return;
      }
      out = (best_buy.score > best_sell.score) ? best_buy : best_sell;
   }
   else
      out = best_buy.valid ? best_buy : best_sell;

   out.agreeing_strategies = 1;
   g_last_dashboard_signal = out.setup + " (" + DoubleToString(out.score, 1) + ")";
}

void SelectBestIndependentSignal(const TradeSignal &candidate,
                                 TradeSignal &best_buy,
                                 TradeSignal &best_sell)
{
   if(!candidate.valid || candidate.direction == 0)
      return;

   TradeSignal scored = candidate;
   if(!ApplyPremiumDiscountFilter(scored))
      return;
   if(!ApplyConfirmedSupportResistanceGate(scored))
      return;
   if(!ApplyRegimeRouting(scored))
      return;
   // V6.33: any surviving signal that sits at a fresh M30 order block in its
   // direction is upgraded - this is how the strategies integrate.
   ApplyOrderBlockConfluence(scored);
   scored.score = ClampDouble(ApplyLearningToScore(scored.score, scored.strategy), 0.0, 100.0);

   if(scored.direction == 1 && (!best_buy.valid || scored.score > best_buy.score))
      best_buy = scored;
   if(scored.direction == -1 && (!best_sell.valid || scored.score > best_sell.score))
      best_sell = scored;
}

bool GetConfirmedDealingRange(DealingRange &range)
{
   range.valid = false;
   range.low = 0.0;
   range.high = 0.0;
   range.equilibrium = 0.0;
   range.equilibrium_band = 0.0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpDealingRangeTF, 0, 480, rates);
   int depth = MathMax(2, InpFractalDepth);
   if(copied < depth * 2 + 20)
      return false;

   double atr = GetATR(_Symbol, InpDealingRangeTF, InpTrendATRPeriod, 1);
   double minimum_width = MathMax(10.0 * _Point,
                                  (atr > 0.0 ? atr * MathMax(0.5, InpMinRangeWidthATR) : 10.0 * _Point));

   // V6.20: reuse the locked range while price still trades inside it, so
   // the premium/discount zones stay stable instead of jumping every fractal.
   if(InpLockRangeUntilBreak && LoadLockedDealingRange(range))
   {
      double break_buffer = MathMax(3.0 * _Point, atr * 0.10);
      bool broke_up = rates[1].close > range.high + break_buffer;
      bool broke_down = rates[1].close < range.low - break_buffer;
      if(!broke_up && !broke_down && range.high - range.low >= minimum_width * 0.75)
         return true;
   }

   // Build a fresh range: walk back through confirmed fractals until the
   // range is wide enough to represent a real dealing range, not a pause.
   double high = 0.0, low = 0.0;
   int highs_found = 0, lows_found = 0;
   for(int i = depth + 1; i < copied - depth; i++)
   {
      if(IsSwingHigh(rates, copied, i, depth))
      {
         high = (highs_found == 0) ? rates[i].high : MathMax(high, rates[i].high);
         highs_found++;
      }
      if(IsSwingLow(rates, copied, i, depth))
      {
         low = (lows_found == 0) ? rates[i].low : MathMin(low, rates[i].low);
         lows_found++;
      }
      if(highs_found >= 2 && lows_found >= 2 && high - low >= minimum_width)
         break;
   }
   if(highs_found < 2 || lows_found < 2 || high <= low)
      return false;
   if(high - low < MathMax(10.0 * _Point, minimum_width * 0.5))
      return false;   // even the widest available structure is too small to be a dealing range

   // V6.20: prefer anchoring to the impulse leg that actually broke structure
   // (external liquidity to external liquidity), the proper ICT convention.
   if(InpUseAnchoredDealingRange)
   {
      int shift_index = -1;
      double shift_level = 0.0;
      int shift_dir = 0;
      if(FindRecentStructureShiftLevel(1, rates, copied, shift_index, shift_level))
         shift_dir = 1;
      else if(FindRecentStructureShiftLevel(-1, rates, copied, shift_index, shift_level))
         shift_dir = -1;

      if(shift_dir != 0 && shift_index > 0)
      {
         double leg_extreme_after = (shift_dir == 1) ? rates[1].high : rates[1].low;
         for(int k = 1; k <= shift_index; k++)
         {
            if(shift_dir == 1)
               leg_extreme_after = MathMax(leg_extreme_after, rates[k].high);
            else
               leg_extreme_after = MathMin(leg_extreme_after, rates[k].low);
         }
         double leg_origin = (shift_dir == 1) ? rates[shift_index].low : rates[shift_index].high;
         int origin_limit = MathMin(copied - depth - 1, shift_index + 60);
         for(int k = shift_index; k <= origin_limit; k++)
         {
            if(shift_dir == 1)
               leg_origin = MathMin(leg_origin, rates[k].low);
            else
               leg_origin = MathMax(leg_origin, rates[k].high);
         }
         double anchored_high = (shift_dir == 1) ? leg_extreme_after : leg_origin;
         double anchored_low = (shift_dir == 1) ? leg_origin : leg_extreme_after;
         if(anchored_high - anchored_low >= minimum_width)
         {
            high = anchored_high;
            low = anchored_low;
         }
      }
   }

   range.high = high;
   range.low = low;
   range.equilibrium = (range.high + range.low) * 0.5;
   range.equilibrium_band = MathMax((range.high - range.low) *
                                    MathMax(0.0, InpEquilibriumBandPercent) / 100.0,
                                    5.0 * _Point);
   range.valid = true;

   if(InpLockRangeUntilBreak)
      StoreLockedDealingRange(range);
   return true;
}

int GetDealingRangeTrend()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpTrendHigherTF1, 0, 260, rates);
   if(copied < 30)
      return 0;

   // Fractal structure remains the primary trend read.  The H1 EMA stack is
   // used only when it is both clearly separated and sloping, which lets the EA
   // recognise a genuine fresh trend before the next fractal is fully confirmed.
   int structure_trend = AnalyzeStructure(rates, copied, MathMax(2, InpFractalDepth)).trend;

   // A new, confirmed break with displacement is allowed to lead the slow
   // fractal read.  This prevents a completed H1/M15 reversal from being
   // labelled as the previous trend while the new fractals are still forming.
   int fresh_trend = GetResponsiveStructureTrend(InpTrendHigherTF1);
   if(fresh_trend != 0 && fresh_trend != structure_trend)
      return fresh_trend;

   double ema50_1 = GetMA(_Symbol, InpTrendHigherTF1, InpTrendEMA50, MODE_EMA, 1);
   double ema50_3 = GetMA(_Symbol, InpTrendHigherTF1, InpTrendEMA50, MODE_EMA, 3);
   double ema200_1 = GetMA(_Symbol, InpTrendHigherTF1, InpTrendEMA200, MODE_EMA, 1);
   double atr = GetATR(_Symbol, InpTrendHigherTF1, InpTrendATRPeriod, 1);
   int ema_trend = 0;

   if(ema50_1 > 0.0 && ema50_3 > 0.0 && ema200_1 > 0.0)
   {
      double separation = MathAbs(ema50_1 - ema200_1);
      double slope = ema50_1 - ema50_3;
      double minimum_separation = MathMax(5.0 * _Point, atr * 0.50);
      double minimum_slope = MathMax(2.0 * _Point, atr * 0.10);
      bool clearly_separated = separation >= minimum_separation;

      if(clearly_separated && ema50_1 > ema200_1 && slope >= minimum_slope)
         ema_trend = 1;
      else if(clearly_separated && ema50_1 < ema200_1 && slope <= -minimum_slope)
         ema_trend = -1;
   }

   // Prefer confirmed fractals whenever the two reads agree or the EMA read is
   // indecisive.  Only a strong, opposing EMA turn can override stale fractals.
   if(structure_trend != 0 && (ema_trend == 0 || ema_trend == structure_trend))
      return structure_trend;
   if(structure_trend == 0 && ema_trend != 0)
      return ema_trend;
   if(structure_trend != 0 && ema_trend == -structure_trend)
      return ema_trend;
   return structure_trend;
}

bool HasEquilibriumBreakoutRetest(int direction, const DealingRange &range)
{
   MqlRates entry[];
   ArraySetAsSeries(entry, true);
   int copied = CopyRates(_Symbol, InpEntryTF, 0,
                          MathMax(30, InpEquilibriumBreakoutLookback + 12), entry);
   // A newly-confirmed M15 CHoCH/BOS with momentum may lead an H1 range read,
   // but it never bypasses the equilibrium break-and-retest requirement below.
   int h1_trend = GetDealingRangeTrend();
   bool fresh_m15_trend = HasFreshStructureShiftMomentum(direction, InpStructureTF);
   if(copied < 12 || (h1_trend != direction && !(h1_trend == 0 && fresh_m15_trend)))
      return false;

   double atr = GetATR(_Symbol, InpEntryTF, InpTrendATRPeriod, 1);
   double tolerance = MathMax(range.equilibrium_band,
                              MathMax(3.0 * _Point, atr * MathMax(0.05, InpEquilibriumRetestATR)));
   bool retest_holds = false;
   if(direction == 1)
      retest_holds = entry[1].low <= range.equilibrium + tolerance &&
                     entry[1].close > range.equilibrium + range.equilibrium_band &&
                     HasBullishCandlePattern(entry);
   else
      retest_holds = entry[1].high >= range.equilibrium - tolerance &&
                     entry[1].close < range.equilibrium - range.equilibrium_band &&
                     HasBearishCandlePattern(entry);
   if(!retest_holds)
      return false;

   int limit = MathMin(copied - 2, MathMax(4, InpEquilibriumBreakoutLookback));
   for(int i = 2; i <= limit; i++)
   {
      bool strong_break = (direction == 1) ?
                          (entry[i].close > range.equilibrium + range.equilibrium_band &&
                           entry[i].close > entry[i].open && BodyRatio(entry[i]) >= 0.60) :
                          (entry[i].close < range.equilibrium - range.equilibrium_band &&
                           entry[i].close < entry[i].open && BodyRatio(entry[i]) >= 0.60);
      if(!strong_break)
         continue;

      bool came_from_other_side = false;
      int older_limit = MathMin(copied - 1, i + 8);
      for(int j = i + 1; j <= older_limit; j++)
      {
         if((direction == 1 && entry[j].close <= range.equilibrium - range.equilibrium_band) ||
            (direction == -1 && entry[j].close >= range.equilibrium + range.equilibrium_band))
         {
            came_from_other_side = true;
            break;
         }
      }
      if(came_from_other_side)
         return true;
   }
   return false;
}

bool FindTwoConfirmedSwingsBefore(const MqlRates &rates[], int copied, int event_index,
                                  int direction, int &recent_index, int &previous_index)
{
   recent_index = -1;
   previous_index = -1;
   int depth = MathMax(2, InpFractalDepth);

   // Only use pivots that were already confirmed before this historical event.
   for(int i = event_index + depth; i < copied - depth; i++)
   {
      bool swing = (direction == 1) ? IsSwingLow(rates, copied, i, depth)
                                    : IsSwingHigh(rates, copied, i, depth);
      if(!swing)
         continue;
      if(recent_index < 0)
         recent_index = i;
      else
      {
         previous_index = i;
         return true;
      }
   }
   return false;
}

bool FindRecentStructureShiftLevel(int direction, const MqlRates &rates[], int copied,
                                   int &shift_index, double &level)
{
   shift_index = -1;
   level = 0.0;
   int limit = MathMin(copied - 8, MathMax(6, InpRangeReversalLookbackBars));

   for(int i = 1; i <= limit; i++)
   {
      int recent_high = -1, previous_high = -1;
      int recent_low = -1, previous_low = -1;
      if(!FindTwoConfirmedSwingsBefore(rates, copied, i, -1, recent_high, previous_high) ||
         !FindTwoConfirmedSwingsBefore(rates, copied, i, 1, recent_low, previous_low))
         continue;

      bool prior_bearish = rates[recent_high].high < rates[previous_high].high &&
                           rates[recent_low].low < rates[previous_low].low;
      bool prior_bullish = rates[recent_high].high > rates[previous_high].high &&
                           rates[recent_low].low > rates[previous_low].low;
      bool bullish_shift = prior_bearish && rates[i].close > rates[previous_high].high;
      bool bearish_shift = prior_bullish && rates[i].close < rates[previous_low].low;

      if((direction == 1 && bullish_shift) || (direction == -1 && bearish_shift))
      {
         shift_index = i;
         level = (direction == 1) ? rates[previous_high].high : rates[previous_low].low;
         return true;
      }
   }
   return false;
}

// A fractal needs candles on both sides before it becomes confirmed.  That is
// excellent for stable structure, but slow at the beginning of a strong move.
// This helper recognises only a genuine fresh leg: CHoCH/BOS, an impulsive
// candle, and acceptance on the correct side of the fast EMA.  It is a trend
// state helper, never a stand-alone entry trigger.
bool HasFreshStructureShiftMomentum(int direction, ENUM_TIMEFRAMES timeframe)
{
   if(!InpUseFreshTrendRecognition || direction == 0)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int required = MathMax(80, InpFreshTrendLookbackBars + InpFractalDepth * 4 + 20);
   int copied = CopyRates(_Symbol, timeframe, 0, required, rates);
   if(copied < 30)
      return false;

   int lookback = MathMin(copied - 8, MathMax(6, InpFreshTrendLookbackBars));
   MarketStructure structure = AnalyzeStructure(rates, copied, MathMax(2, InpFractalDepth));
   int shift_index = -1;
   double shift_level = 0.0;
   bool confirmed_shift = FindRecentStructureShiftLevel(direction, rates, copied,
                                                         shift_index, shift_level) &&
                          shift_index <= lookback;
   bool current_break = (direction == 1) ? (structure.bullish_choch || structure.bullish_bos)
                                         : (structure.bearish_choch || structure.bearish_bos);
   if(!confirmed_shift && !current_break)
      return false;

   double atr = GetATR(_Symbol, timeframe, InpTrendATRPeriod, 1);
   double ema_fast_1 = GetMA(_Symbol, timeframe, InpTrendEMAFast, MODE_EMA, 1);
   double ema_fast_3 = GetMA(_Symbol, timeframe, InpTrendEMAFast, MODE_EMA, 3);
   if(atr <= 0.0 || ema_fast_1 <= 0.0 || ema_fast_3 <= 0.0)
      return false;

   bool impulse_found = false;
   int impulse_limit = MathMin(lookback, (confirmed_shift ? shift_index : 4));
   for(int i = 1; i <= MathMax(1, impulse_limit); i++)
   {
      double candle_range = rates[i].high - rates[i].low;
      bool directional_candle = (direction == 1) ? rates[i].close > rates[i].open
                                                  : rates[i].close < rates[i].open;
      if(directional_candle && candle_range >= atr * MathMax(0.10, InpFreshTrendImpulseATR) &&
         BodyRatio(rates[i]) >= MathMax(0.10, InpFreshTrendMinBodyRatio))
      {
         impulse_found = true;
         break;
      }
   }

   bool price_accepted = (direction == 1) ? rates[1].close > ema_fast_1
                                           : rates[1].close < ema_fast_1;
   bool fast_ema_turning = (direction == 1) ? ema_fast_1 >= ema_fast_3
                                             : ema_fast_1 <= ema_fast_3;
   return impulse_found && price_accepted && fast_ema_turning;
}

int GetResponsiveStructureTrend(ENUM_TIMEFRAMES timeframe)
{
   if(HasFreshStructureShiftMomentum(1, timeframe))
      return 1;
   if(HasFreshStructureShiftMomentum(-1, timeframe))
      return -1;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, timeframe, 0, 140, rates);
   if(copied < 30)
      return 0;
   return AnalyzeStructure(rates, copied, MathMax(2, InpFractalDepth)).trend;
}

bool HasRangeReversalOrigin(int direction, const DealingRange &range,
                            const MqlRates &rates[], int copied, int shift_index)
{
   int limit = MathMin(copied - 2, MathMax(6, InpRangeReversalLookbackBars));
   // The reversal candle must precede the CHoCH, so it is older in a series array.
   for(int i = shift_index + 1; i <= limit; i++)
   {
      bool correct_value = (direction == 1) ?
                           rates[i].close < range.equilibrium - range.equilibrium_band :
                           rates[i].close > range.equilibrium + range.equilibrium_band;
      if(!correct_value)
         continue;

      bool confirmation = (direction == 1) ?
                          (IsBullishPinBar(rates[i]) || IsBullishEngulfing(rates, i)) :
                          (IsBearishPinBar(rates[i]) || IsBearishEngulfing(rates, i));
      if(!confirmation)
         continue;

      // The reversal has to originate close to the outer range boundary, not in the middle.
      double boundary_room = range.equilibrium_band * 2.0;
      bool at_range_edge = (direction == 1) ? rates[i].low <= range.low + boundary_room
                                             : rates[i].high >= range.high - boundary_room;
      if(at_range_edge)
         return true;
   }
   return false;
}

bool HasM5LevelRetest(int direction, double level)
{
   MqlRates entry[];
   ArraySetAsSeries(entry, true);
   int copied = CopyRates(_Symbol, InpEntryTF, 0, 12, entry);
   if(copied < 5 || level <= 0.0)
      return false;

   double atr = GetATR(_Symbol, InpEntryTF, InpTrendATRPeriod, 1);
   double tolerance = MathMax(5.0 * _Point, atr * MathMax(0.05, InpEquilibriumRetestATR));
   if(direction == 1)
      return entry[1].low <= level + tolerance && entry[1].close > level &&
             (IsBullishPinBar(entry[1]) || IsBullishEngulfing(entry, 1) ||
              (entry[1].close > entry[1].open && BodyRatio(entry[1]) >= 0.60));

   return entry[1].high >= level - tolerance && entry[1].close < level &&
          (IsBearishPinBar(entry[1]) || IsBearishEngulfing(entry, 1) ||
           (entry[1].close < entry[1].open && BodyRatio(entry[1]) >= 0.60));
}

bool HasRangeReversalContinuation(int direction, const DealingRange &range, double &break_level)
{
   break_level = 0.0;
   if(GetDealingRangeTrend() != 0)
      return false;  // this path is specifically for reversals inside an H1 range

   MqlRates structure[];
   ArraySetAsSeries(structure, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0,
                          MathMax(80, InpRangeReversalLookbackBars + 30), structure);
   if(copied < 30)
      return false;

   int shift_index = -1;
   if(!FindRecentStructureShiftLevel(direction, structure, copied, shift_index, break_level))
      return false;
   if(!HasRangeReversalOrigin(direction, range, structure, copied, shift_index))
      return false;
   return HasM5LevelRetest(direction, break_level);
}

bool BuildRangeReversalSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   DealingRange range;
   if(!GetConfirmedDealingRange(range) || GetDealingRangeTrend() != 0)
      return false;

   double break_level = 0.0;
   if(!HasRangeReversalContinuation(direction, range, break_level))
      return false;

   MqlRates entry[];
   ArraySetAsSeries(entry, true);
   if(CopyRates(_Symbol, InpEntryTF, 0, 12, entry) < 5)
      return false;

   double entry_price = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = GetInitialStopBuffer(InpEntryTF);
   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "SRBounce";
   signal.setup = (direction == 1) ? "RangeBullishReversal_Retest" : "RangeBearishReversal_Retest";
   signal.reason = (direction == 1) ?
                   "discount support rejection, M15 bullish CHoCH, and M5 resistance-to-support retest" :
                   "premium resistance rejection, M15 bearish CHoCH, and M5 support-to-resistance retest";
   signal.score = ClampDouble(50.0 + 10.0 + 15.0 + 15.0 + InpRangeReversalScoreBonus, 0.0, 100.0);
   signal.sl = (direction == 1) ? NormalizePrice(MathMin(entry[1].low, break_level) - buffer)
                                : NormalizePrice(MathMax(entry[1].high, break_level) + buffer);
   signal.tp = (direction == 1) ? NormalizePrice(entry_price + MathAbs(entry_price - signal.sl) * InpDefaultRiskReward)
                                : NormalizePrice(entry_price - MathAbs(entry_price - signal.sl) * InpDefaultRiskReward);

   if(!SetEquilibriumContinuationTarget(signal))
   {
      signal.valid = false;
      return false;
   }
   return true;
}

bool HasOuterRangeBreakoutConfirmation(int direction, const DealingRange &range, double &break_level)
{
   break_level = (direction == 1) ? range.high : range.low;

   MqlRates structure[];
   ArraySetAsSeries(structure, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, 100, structure);
   if(copied < 30)
      return false;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   double threshold = MathMax(3.0 * _Point, atr * MathMax(0.05, InpOuterRangeBreakoutATR));
   bool strong_close = (direction == 1) ?
                       (structure[1].close > range.high + threshold &&
                        structure[1].close > structure[1].open && BodyRatio(structure[1]) >= 0.60) :
                       (structure[1].close < range.low - threshold &&
                        structure[1].close < structure[1].open && BodyRatio(structure[1]) >= 0.60);
   if(!strong_close)
      return false;

   int shift_index = -1;
   double shift_level = 0.0;
   if(!FindRecentStructureShiftLevel(direction, structure, copied, shift_index, shift_level))
      return false;

   if(!InpOuterRangeRequiresM5Confirm)
      return true;

   MqlRates entry[];
   ArraySetAsSeries(entry, true);
   int entry_copied = CopyRates(_Symbol, InpEntryTF, 0, 8, entry);
   if(entry_copied < 4)
      return false;

   if(direction == 1)
      return entry[1].close > range.high &&
             entry[1].close > entry[1].open && BodyRatio(entry[1]) >= 0.55;
   return entry[1].close < range.low &&
          entry[1].close < entry[1].open && BodyRatio(entry[1]) >= 0.55;
}

bool BuildOuterRangeBreakoutSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   DealingRange range;
   if(!GetConfirmedDealingRange(range))
      return false;

   double break_level = 0.0;
   if(!HasOuterRangeBreakoutConfirmation(direction, range, break_level))
      return false;

   MqlRates structure[];
   ArraySetAsSeries(structure, true);
   if(CopyRates(_Symbol, InpStructureTF, 0, 20, structure) < 5)
      return false;

   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = GetInitialStopBuffer(InpEntryTF);
   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "TrendFollowing";
   signal.setup = (direction == 1) ? "PremiumHighBreak_CHoCH_Buy" : "DiscountLowBreak_CHoCH_Sell";
   signal.reason = (direction == 1) ?
                   "strong M15 premium-high break with bullish CHoCH and M5 follow-through" :
                   "strong M15 discount-low break with bearish CHoCH and M5 follow-through";
   signal.score = 85.0;
   signal.sl = (direction == 1) ? NormalizePrice(MathMin(structure[1].low, break_level) - buffer)
                                : NormalizePrice(MathMax(structure[1].high, break_level) + buffer);
   signal.tp = (direction == 1) ? NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward)
                                : NormalizePrice(entry - MathAbs(entry - signal.sl) * InpDefaultRiskReward);

   if(!SetEquilibriumContinuationTarget(signal))
   {
      signal.valid = false;
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Independent FVG retest strategy                                  |
//+------------------------------------------------------------------+
bool IsFVGMiddleCandleDisplacement(int direction, const MqlRates &rates[], int index, double atr)
{
   int middle = index + 1;
   double body = MathAbs(rates[middle].close - rates[middle].open);
   double minimum_body = MathMax(5.0 * _Point, atr * MathMax(0.10, InpFVGMinDisplacementATR));
   bool directional_body = (direction == 1) ? rates[middle].close > rates[middle].open
                                            : rates[middle].close < rates[middle].open;
   return directional_body && BodyRatio(rates[middle]) >= 0.60 && body >= minimum_body;
}

bool WasFVGTouchedBeforeCurrentRetest(const MqlRates &rates[], int formation_index,
                                      const PriceZone &zone)
{
   // Index 1 is the current closed M15 retest candle.  Earlier retests invalidate
   // the setup: this strategy trades the first quality return to a fresh imbalance.
   for(int j = 2; j < formation_index; j++)
   {
      if(rates[j].low <= zone.high && rates[j].high >= zone.low)
         return true;
   }
   return false;
}

bool IsCurrentM15FVGRetest(int direction, const MqlRates &rates[], const PriceZone &zone)
{
   if(!zone.valid)
      return false;

   double width = zone.high - zone.low;
   if(width <= 0.0)
      return false;

   MqlRates retest = rates[1];
   bool overlaps_zone = retest.low <= zone.high && retest.high >= zone.low;
   double penetration = (direction == 1) ? zone.high - retest.low : retest.high - zone.low;
   double required_penetration = width * ClampDouble(InpFVGMinRetestPercent, 0.0, 100.0) / 100.0;
   double midpoint = (zone.low + zone.high) * 0.5;
   bool holds_direction = (direction == 1) ?
                          (retest.close > midpoint && retest.close > zone.low) :
                          (retest.close < midpoint && retest.close < zone.high);
   return overlaps_zone && penetration >= required_penetration && holds_direction;
}

bool FindFreshRetestedFVG(int direction, const MqlRates &rates[], int copied,
                          PriceZone &zone, int &formation_index)
{
   zone = PriceZoneEmpty();
   formation_index = -1;
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   double minimum_gap = MathMax(3.0 * _Point, InpFVGMinGapPoints * _Point);
   int max_index = MathMin(copied - 3,
                           MathMin(MathMax(3, InpFVGLookbackBars), MathMax(3, InpFVGMaxAgeBars)));

   // Search newest to oldest so two valid gaps cannot produce an arbitrary old entry.
   for(int i = 3; i <= max_index; i++)
   {
      double gap = (direction == 1) ? rates[i].low - rates[i + 2].high
                                    : rates[i + 2].low - rates[i].high;
      if(gap < minimum_gap || !IsFVGMiddleCandleDisplacement(direction, rates, i, atr))
         continue;

      PriceZone candidate = PriceZoneEmpty();
      candidate.valid = true;
      candidate.direction = direction;
      candidate.low = (direction == 1) ? rates[i + 2].high : rates[i].high;
      candidate.high = (direction == 1) ? rates[i].low : rates[i + 2].low;
      candidate.timeframe = InpStructureTF;
      candidate.start_time = rates[i + 2].time;
      candidate.end_time = rates[i].time;
      candidate.label = (direction == 1) ? "Bullish FVG" : "Bearish FVG";

      if(WasFVGTouchedBeforeCurrentRetest(rates, i, candidate))
         continue;
      if(!IsCurrentM15FVGRetest(direction, rates, candidate))
         continue;

      zone = candidate;
      formation_index = i;
      return true;
   }
   return false;
}

bool FindFVGLinkedBreakOfStructure(int direction, const MqlRates &rates[], int copied,
                                   int fvg_formation_index, int &bos_index, double &bos_level)
{
   bos_index = -1;
   bos_level = 0.0;
   int first = MathMax(2, fvg_formation_index);
   int last = MathMin(copied - 8,
                      fvg_formation_index + MathMax(3, InpFVGBOSLookbackBars));

   // The break must exist before, or as part of, the FVG displacement.  A later
   // random break does not turn an old gap into a valid continuation setup.
   for(int i = first; i <= last; i++)
   {
      int recent_high = -1, previous_high = -1;
      int recent_low = -1, previous_low = -1;
      if(!FindTwoConfirmedSwingsBefore(rates, copied, i, -1, recent_high, previous_high) ||
         !FindTwoConfirmedSwingsBefore(rates, copied, i, 1, recent_low, previous_low))
         continue;

      double level = (direction == 1) ? rates[recent_high].high : rates[recent_low].low;
      bool broke = (direction == 1) ? rates[i].close > level : rates[i].close < level;
      if(broke)
      {
         bos_index = i;
         bos_level = level;
         return true;
      }
   }
   return false;
}

bool HasFVGM15StructureContext(int direction, const MqlRates &rates[], int copied,
                               int fvg_formation_index, bool &has_recent_shift, bool &has_bos)
{
   has_recent_shift = false;
   has_bos = false;
   MarketStructure structure = AnalyzeStructure(rates, copied, MathMax(2, InpStructureSwingDepth));
   int shift_index = -1;
   double shift_level = 0.0;
   has_recent_shift = FindRecentStructureShiftLevel(direction, rates, copied, shift_index, shift_level);
   bool fresh_trend = HasFreshStructureShiftMomentum(direction, InpStructureTF);
   has_recent_shift = has_recent_shift || fresh_trend;
   int bos_index = -1;
   double bos_level = 0.0;
   has_bos = FindFVGLinkedBreakOfStructure(direction, rates, copied, fvg_formation_index,
                                            bos_index, bos_level);
   if(InpFVGRequireBreakOfStructure && !has_bos)
      return false;

   bool m15_aligned = GetResponsiveStructureTrend(InpStructureTF) == direction ||
                      has_recent_shift || has_bos;
   if(InpFVGRequireM15Structure && !m15_aligned)
      return false;

   // Do not fade an established H1 trend.  A fresh M15 CHoCH is the only allowed
   // exception, after which the premium/discount filter still has final authority.
   int h1_trend = GetDealingRangeTrend();
   if(h1_trend == -direction && !has_recent_shift && !has_bos)
      return false;
   return true;
}

bool HasFVGM5Confirmation(int direction, const PriceZone &zone,
                          datetime m15_retest_time, double &rejection_extreme)
{
   rejection_extreme = (direction == 1) ? zone.low : zone.high;
   if(!InpFVGRequireM5Confirmation)
      return true;

   MqlRates entry[];
   ArraySetAsSeries(entry, true);
   int copied = CopyRates(_Symbol, InpEntryTF, 0, 10, entry);
   if(copied < 5)
      return false;

   bool touched_after_retest = false;
   int recent_limit = MathMin(4, copied - 1);
   for(int i = 1; i <= recent_limit; i++)
   {
      if(entry[i].time < m15_retest_time)
         continue;
      if(entry[i].low <= zone.high && entry[i].high >= zone.low)
      {
         touched_after_retest = true;
         if(direction == 1)
            rejection_extreme = MathMin(rejection_extreme, entry[i].low);
         else
            rejection_extreme = MathMax(rejection_extreme, entry[i].high);
      }
   }
   if(!touched_after_retest)
      return false;

   double midpoint = (zone.low + zone.high) * 0.5;
   bool directional_close = (direction == 1) ?
                            (entry[1].close > midpoint && entry[1].close > zone.low) :
                            (entry[1].close < midpoint && entry[1].close < zone.high);
   bool rejection_candle = (direction == 1) ?
                           (HasBullishCandlePattern(entry) ||
                            (entry[1].close > entry[1].open && BodyRatio(entry[1]) >= 0.55)) :
                           (HasBearishCandlePattern(entry) ||
                            (entry[1].close < entry[1].open && BodyRatio(entry[1]) >= 0.55));
   return directional_close && rejection_candle;
}

bool BuildFVGRetestSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);

   MqlRates structure[];
   ArraySetAsSeries(structure, true);
   int lookback = MathMax(80, MathMax(InpFVGLookbackBars, InpFVGMaxAgeBars) + 12);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, lookback, structure);
   if(copied < 30)
      return false;

   PriceZone fvg;
   int formation_index = -1;
   if(!FindFreshRetestedFVG(direction, structure, copied, fvg, formation_index))
      return false;

   bool has_recent_shift = false;
   bool has_bos = false;
   if(!HasFVGM15StructureContext(direction, structure, copied, formation_index,
                                  has_recent_shift, has_bos))
      return false;

   double m5_rejection_extreme = 0.0;
   if(!HasFVGM5Confirmation(direction, fvg, structure[1].time, m5_rejection_extreme))
      return false;

   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF),
                            GetATR(_Symbol, InpEntryTF, InpTrendATRPeriod, 1) * 0.20);
   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "FVGRetest";
   signal.setup = (direction == 1) ? "BullishFVG_RetestContinuation" : "BearishFVG_RetestContinuation";
   signal.reason = (direction == 1) ?
                   "fresh M15 bullish FVG first retest with M5 bullish rejection and structure confirmation" :
                   "fresh M15 bearish FVG first retest with M5 bearish rejection and structure confirmation";
   signal.score = 80.0;
   if(has_bos)
   {
      signal.score += 5.0;
      signal.reason = AppendToken(signal.reason, "linked M15 BOS");
   }
   if(has_recent_shift)
   {
      signal.score += 6.0;
      signal.reason = AppendToken(signal.reason, "recent M15 CHoCH");
   }
   if(GetDealingRangeTrend() == direction)
   {
      signal.score += 4.0;
      signal.reason = AppendToken(signal.reason, "H1 trend aligned");
   }

   signal.sl = (direction == 1) ? NormalizePrice(MathMin(fvg.low, m5_rejection_extreme) - buffer)
                                : NormalizePrice(MathMax(fvg.high, m5_rejection_extreme) + buffer);
   signal.tp = (direction == 1) ? NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward)
                                : NormalizePrice(entry - MathAbs(entry - signal.sl) * InpDefaultRiskReward);

   if(!SetEquilibriumContinuationTarget(signal))
   {
      signal.valid = false;
      return false;
   }
   return true;
}

double FindQualifiedFractalTarget(int direction, const MqlRates &rates[], int copied,
                                  double entry, double minimum_distance)
{
   double target = 0.0;
   int depth = MathMax(2, InpFractalDepth);
   for(int i = depth + 1; i < copied - depth; i++)
   {
      bool swing = (direction == 1) ? IsSwingHigh(rates, copied, i, depth)
                                    : IsSwingLow(rates, copied, i, depth);
      if(!swing)
         continue;

      double candidate = (direction == 1) ? rates[i].high : rates[i].low;
      double distance = (direction == 1) ? candidate - entry : entry - candidate;
      if(distance < minimum_distance)
         continue;

      if(target <= 0.0 ||
         (direction == 1 && candidate < target) ||
         (direction == -1 && candidate > target))
         target = candidate;
   }
   return target;
}

double FindNextQualifiedM15Target(int direction, double entry, double minimum_distance,
                                  double beyond_target)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M15, 0, MathMax(1000, InpM15HistoricalLookback) + 10, rates);
   int depth = MathMax(2, InpFractalDepth);
   if(copied < depth * 2 + 12)
      return 0.0;

   double target = 0.0;
   for(int i = depth + 1; i < copied - depth; i++)
   {
      bool swing = (direction == 1) ? IsSwingHigh(rates, copied, i, depth)
                                    : IsSwingLow(rates, copied, i, depth);
      if(!swing)
         continue;

      double candidate = (direction == 1) ? rates[i].high : rates[i].low;
      double distance = (direction == 1) ? candidate - entry : entry - candidate;
      bool beyond_previous = (direction == 1) ? candidate > beyond_target + _Point
                                              : candidate < beyond_target - _Point;
      if(distance < minimum_distance || !beyond_previous)
         continue;

      if(target <= 0.0 ||
         (direction == 1 && candidate < target) ||
         (direction == -1 && candidate > target))
         target = candidate;
   }
   return target;
}

void ApplyHistoricalM15Target(int direction, double entry, double sl, double &tp)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int lookback = MathMax(1000, InpM15HistoricalLookback);
   int copied = CopyRates(_Symbol, PERIOD_M15, 0, lookback + 10, rates);
   if(copied < MathMax(30, InpFractalDepth * 2 + 10))
      return;

   double target = FindQualifiedFractalTarget(direction, rates, copied, entry,
                                              risk * MathMax(1.0, InpMinRiskReward));
   if(target > 0.0)
      tp = NormalizePrice(target);
}

bool SetEquilibriumContinuationTarget(TradeSignal &signal)
{
   MqlRates structure[];
   ArraySetAsSeries(structure, true);
   int m15_target_lookback = MathMax(InpSRLookbackBars + 30,
                                     MathMax(1000, InpM15HistoricalLookback) + 10);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, m15_target_lookback, structure);
   if(copied < 40)
      return false;

   double entry = (signal.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double risk = MathAbs(entry - signal.sl);
   if(risk <= 0.0)
      return false;
   double minimum_distance = risk * InpMinRiskReward;

   double tolerance = GetSRZoneTolerance();
   PriceZone support = FindSRZone(structure, copied, 1, tolerance);
   PriceZone resistance = FindSRZone(structure, copied, -1, tolerance);
   double target = 0.0;

   if(signal.direction == 1)
   {
      if(resistance.valid && resistance.low - entry >= minimum_distance)
         target = resistance.low;
   }
   else
   {
      if(support.valid && entry - support.high >= minimum_distance)
         target = support.high;
   }

   double m15_swing_target = FindQualifiedFractalTarget(signal.direction, structure, copied,
                                                         entry, minimum_distance);
   if(m15_swing_target > 0.0 &&
      (target <= 0.0 ||
       (signal.direction == 1 && m15_swing_target < target) ||
       (signal.direction == -1 && m15_swing_target > target)))
      target = m15_swing_target;

   MqlRates h1[];
   ArraySetAsSeries(h1, true);
   int h1_copied = CopyRates(_Symbol, InpTrendHigherTF1, 0, 260, h1);
   if(h1_copied >= 30)
   {
      double h1_swing_target = FindQualifiedFractalTarget(signal.direction, h1, h1_copied,
                                                           entry, minimum_distance);
      if(h1_swing_target > 0.0 &&
         (target <= 0.0 ||
          (signal.direction == 1 && h1_swing_target < target) ||
          (signal.direction == -1 && h1_swing_target > target)))
         target = h1_swing_target;
   }

   ENUM_TIMEFRAMES major_target_tfs[2] = {PERIOD_M30, PERIOD_H4};
   for(int i = 0; i < 2; i++)
   {
      MqlRates major[];
      ArraySetAsSeries(major, true);
      int bars = (major_target_tfs[i] == PERIOD_M30) ? 700 : 260;
      int major_copied = CopyRates(_Symbol, major_target_tfs[i], 0, bars, major);
      if(major_copied < 30)
         continue;

      double major_target = FindQualifiedFractalTarget(signal.direction, major, major_copied,
                                                        entry, minimum_distance);
      if(major_target > 0.0 &&
         (target <= 0.0 ||
          (signal.direction == 1 && major_target < target) ||
          (signal.direction == -1 && major_target > target)))
         target = major_target;
   }

   if(target <= 0.0)
      return false;

   signal.tp = NormalizePrice(target);
   return true;
}

bool ApplyPremiumDiscountFilter(TradeSignal &signal)
{
   g_last_value_filter_reason = "";
   if(!InpUsePremiumDiscountFilter || !signal.valid)
      return signal.valid;

   // V6.20: trendline, BOS-retest, and NFP setups carry their own structural
   // confirmation; the equilibrium band rules do not apply to them.
   if(InpSelfConfirmedBypassFilters && IsSelfConfirmedSetup(signal.setup))
      return true;

   DealingRange range;
   if(!GetConfirmedDealingRange(range))
   {
      g_last_value_filter_reason = "No trade: no confirmed fractal dealing range on the range timeframe";
      return false;
   }

   double price = (signal.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool at_equilibrium = MathAbs(price - range.equilibrium) <= range.equilibrium_band;
   bool in_discount = price < range.equilibrium - range.equilibrium_band;
   bool in_premium = price > range.equilibrium + range.equilibrium_band;

   if(at_equilibrium)
   {
      g_last_value_filter_reason = "No trade: price is inside the equilibrium no-trade band";
      return false;
   }

   // Discount is a buy-only area until price actually breaks the discount low
   // with bearish CHoCH and M5 continuation. This prevents premature countertrend sells.
   if(signal.direction == -1 && in_discount)
   {
      double discount_break_level = 0.0;
      if(InpEnableOuterRangeBreakouts &&
         HasOuterRangeBreakoutConfirmation(-1, range, discount_break_level) &&
         SetEquilibriumContinuationTarget(signal))
      {
         signal.score = ClampDouble(signal.score + 15.0, 0.0, 100.0);
         signal.setup = signal.setup + "_DiscountBreakContinuation";
         signal.reason = AppendToken(signal.reason,
                                     "discount low broken with bearish CHoCH, M5 continuation, and major lower-low target");
         return true;
      }

      g_last_value_filter_reason = "No trade: discount is buy-only until its low is broken with bearish CHoCH and M5 continuation";
      return false;
   }

   bool correct_value_area = (signal.direction == 1) ? in_discount : in_premium;
   if(correct_value_area)
   {
      // V6.20: the 62-79% retracement pocket (OTE) is the highest-quality
      // part of discount/premium; entries inside it earn a bonus.
      if(PriceInOTEZone(signal.direction, range, price))
      {
         signal.score = ClampDouble(signal.score + MathMax(0.0, InpOTEScoreBonus), 0.0, 100.0);
         signal.reason = AppendToken(signal.reason, "OTE zone entry (62-79% retracement)");
      }
      return true;
   }

   double outer_break_level = 0.0;
   if(InpEnableOuterRangeBreakouts &&
      HasOuterRangeBreakoutConfirmation(signal.direction, range, outer_break_level) &&
      SetEquilibriumContinuationTarget(signal))
   {
      signal.score = ClampDouble(signal.score + 15.0, 0.0, 100.0);
      signal.setup = signal.setup + "_OuterRangeBreak";
      signal.reason = AppendToken(signal.reason,
                                  "confirmed outer-range break with CHoCH, M5 follow-through, and historical target");
      return true;
   }

   if(HasEquilibriumBreakoutRetest(signal.direction, range) &&
      SetEquilibriumContinuationTarget(signal))
   {
      signal.score = ClampDouble(signal.score + 15.0, 0.0, 100.0);
      signal.setup = signal.setup + "_EQBreakRetest";
      signal.reason = AppendToken(signal.reason, "confirmed equilibrium break, retest, trend alignment, and next-level target");
      return true;
   }

   double range_break_level = 0.0;
   if(InpAllowRangeReversalEntries &&
      HasRangeReversalContinuation(signal.direction, range, range_break_level) &&
      SetEquilibriumContinuationTarget(signal))
   {
      signal.score = ClampDouble(signal.score + InpRangeReversalScoreBonus, 0.0, 100.0);
      signal.setup = signal.setup + "_RangeReversalRetest";
      signal.reason = AppendToken(signal.reason,
                                  "H1 range reversal: outer-range rejection, M15 CHoCH, and M5 broken-level retest");
      return true;
   }

   g_last_value_filter_reason = (signal.direction == 1) ?
                                "No trade: buy above equilibrium needs a confirmed bullish break and retest" :
                                "No trade: sell below equilibrium needs a confirmed bearish break and retest";
   return false;
}

// V6.10: this gate now enforces the second-retest entry rule. The closed
// candle must be at least the SECOND distinct retest of the level before
// any entry is allowed, both for intact SR and for flipped levels.
bool ApplyConfirmedSupportResistanceGate(TradeSignal &signal)
{
   if(!InpRequireConfirmedSREntry || !signal.valid)
      return signal.valid;

   // V6.20: trendline, BOS-retest, and NFP setups confirm themselves against
   // their own structure; the horizontal SR gate does not apply to them.
   // V6.33: the OB+SR setup embeds its own SR confluence check, so the
   // horizontal gate is bypassed for it too (premium/discount still applies).
   if(InpSelfConfirmedBypassFilters &&
      (IsSelfConfirmedSetup(signal.setup) || StringFind(signal.setup, "OB_SR_") >= 0))
      return true;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, InpSRLookbackBars + 30, rates);
   if(copied < 40)
   {
      g_last_value_filter_reason = "No trade: not enough M15 data to confirm support/resistance";
      return false;
   }

   double tolerance = GetSRZoneTolerance();
   double close1 = rates[1].close;
   PriceZone support = FindSRZone(rates, copied, 1, tolerance);
   PriceZone resistance = FindSRZone(rates, copied, -1, tolerance);
   ScanCustomSupportResistance(rates, copied, tolerance);
   PriceZone custom_support = CustomSRZone(1, tolerance);
   PriceZone custom_resistance = CustomSRZone(-1, tolerance);
   if(custom_support.valid && (!support.valid ||
      MathAbs(close1 - (custom_support.low + custom_support.high) * 0.5) <
      MathAbs(close1 - (support.low + support.high) * 0.5)))
      support = custom_support;
   if(custom_resistance.valid && (!resistance.valid ||
      MathAbs(close1 - (custom_resistance.low + custom_resistance.high) * 0.5) <
      MathAbs(close1 - (resistance.low + resistance.high) * 0.5)))
      resistance = custom_resistance;

   PriceZone role_buy = FindBrokenRetestedZone(rates, copied, 1, tolerance);
   PriceZone role_sell = FindBrokenRetestedZone(rates, copied, -1, tolerance);
   double role_buy_level = (role_buy.low + role_buy.high) * 0.5;
   double role_sell_level = (role_sell.low + role_sell.high) * 0.5;
   bool role_buy_m5 = role_buy.valid &&
                       (!InpSRRoleReversalRequireM5 || HasM5LevelRetest(1, role_buy_level));
   bool role_sell_m5 = role_sell.valid &&
                        (!InpSRRoleReversalRequireM5 || HasM5LevelRetest(-1, role_sell_level));

   if(signal.direction == 1)
   {
      // A buy at former resistance is allowed only after a real M15 break and
      // a confirmed retest of that level as support on M5.
      if(role_buy.valid)
      {
         if(!role_buy_m5)
         {
            g_last_value_filter_reason = "No trade: broken resistance has not yet held as M5 support";
            return false;
         }
         // V6.20: a resistance-to-support buy is never taken straight against
         // a bearish H1 regime unless a fresh M15 bullish shift backs it.
         // This is the losing GBPUSD role-reversal buy from the journal, fixed.
         if(GetDealingRangeTrend() == -1 && !HasFreshStructureShiftMomentum(1, InpStructureTF))
         {
            g_last_value_filter_reason = "No trade: flipped-support buy blocked against a bearish H1 regime";
            return false;
         }
         // V6.10: the flipped level must be on its second distinct retest.
         if(!HasSecondRetestConfirmation(rates, copied, role_buy, 1))
         {
            g_last_value_filter_reason = "No trade: waiting for the second distinct retest of the flipped support";
            return false;
         }
         if(!SetEquilibriumContinuationTarget(signal))
         {
            g_last_value_filter_reason = "No trade: resistance-to-support buy has no valid historical high target";
            return false;
         }
         signal.score = ClampDouble(signal.score + 8.0, 0.0, 100.0);
         signal.setup = signal.setup + "_ConfirmedRtoS";
         signal.reason = AppendToken(signal.reason,
                                     "M15 resistance break, second retest held as M5 support; TP High 1 to TP High 3 ladder armed");
         return true;
      }

      // At intact support, buy only from a genuine lower-wick rejection.  Trend,
      // FVG, and momentum signals are not allowed to bypass this confirmation.
      bool bullish_support_wick = support.valid && rates[1].low <= support.high &&
                                  rates[1].close > support.low && IsBullishPinBar(rates[1]);
      if(bullish_support_wick)
      {
         // V6.10: only the second distinct retest of intact support may be bought.
         if(!HasSecondRetestConfirmation(rates, copied, support, 1))
         {
            g_last_value_filter_reason = "No trade: waiting for the second distinct retest of support";
            return false;
         }
         signal.score = ClampDouble(signal.score + 4.0, 0.0, 100.0);
         signal.setup = signal.setup + "_SupportWick";
         signal.reason = AppendToken(signal.reason, "second retest of intact support confirmed by bullish lower-wick rejection");
         return true;
      }

      g_last_value_filter_reason = "No trade: buy needs a second-retest bullish wick at intact support or a confirmed resistance-to-support retest";
      return false;
   }

   // Mirror rule: an intact resistance can produce only a bearish wick sell.
   if(role_sell.valid)
   {
      if(!role_sell_m5)
      {
         g_last_value_filter_reason = "No trade: broken support has not yet held as M5 resistance";
         return false;
      }
      // V6.20 mirror rule: no support-to-resistance sell against a bullish H1
      // regime without a fresh M15 bearish shift.
      if(GetDealingRangeTrend() == 1 && !HasFreshStructureShiftMomentum(-1, InpStructureTF))
      {
         g_last_value_filter_reason = "No trade: flipped-resistance sell blocked against a bullish H1 regime";
         return false;
      }
      if(!HasSecondRetestConfirmation(rates, copied, role_sell, -1))
      {
         g_last_value_filter_reason = "No trade: waiting for the second distinct retest of the flipped resistance";
         return false;
      }
      if(!SetEquilibriumContinuationTarget(signal))
      {
         g_last_value_filter_reason = "No trade: support-to-resistance sell has no valid historical low target";
         return false;
      }
      signal.score = ClampDouble(signal.score + 8.0, 0.0, 100.0);
      signal.setup = signal.setup + "_ConfirmedStoR";
      signal.reason = AppendToken(signal.reason,
                                  "M15 support break, second retest held as M5 resistance; TP Low 1 to TP Low 3 ladder armed");
      return true;
   }

   bool bearish_resistance_wick = resistance.valid && rates[1].high >= resistance.low &&
                                  rates[1].close < resistance.high && IsBearishPinBar(rates[1]);
   if(bearish_resistance_wick)
   {
      if(!HasSecondRetestConfirmation(rates, copied, resistance, -1))
      {
         g_last_value_filter_reason = "No trade: waiting for the second distinct retest of resistance";
         return false;
      }
      signal.score = ClampDouble(signal.score + 4.0, 0.0, 100.0);
      signal.setup = signal.setup + "_ResistanceWick";
      signal.reason = AppendToken(signal.reason, "second retest of intact resistance confirmed by bearish upper-wick rejection");
      return true;
   }

   g_last_value_filter_reason = "No trade: sell needs a second-retest bearish wick at intact resistance or a confirmed support-to-resistance retest";
   return false;
}

void AddSignalToBasket(const TradeSignal &signal,
                       double &buy_score,
                       double &sell_score,
                       int &buy_count,
                       int &sell_count,
                       TradeSignal &best_buy,
                       TradeSignal &best_sell)
{
   if(!signal.valid || signal.direction == 0)
      return;

   double learned_score = ApplyLearningToScore(signal.score, signal.strategy);

   if(signal.direction == 1)
   {
      buy_score += learned_score;
      buy_count++;
      if(!best_buy.valid || learned_score > best_buy.score)
      {
         best_buy = signal;
         best_buy.score = learned_score;
      }
   }
   else
   {
      sell_score += learned_score;
      sell_count++;
      if(!best_sell.valid || learned_score > best_sell.score)
      {
         best_sell = signal;
         best_sell.score = learned_score;
      }
   }
}

//+------------------------------------------------------------------+
//| SRBounce                                                         |
//+------------------------------------------------------------------+
void EvaluateSRBounceSignal(TradeSignal &signal)
{
   EmptySignal(signal);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, InpSRLookbackBars + 30, rates);
   if(copied < 80)
      return;

   double tolerance = GetSRZoneTolerance();
   double close1 = rates[1].close;
   double high1 = rates[1].high;
   double low1 = rates[1].low;

   PriceZone support = FindSRZone(rates, copied, 1, tolerance);
   PriceZone resistance = FindSRZone(rates, copied, -1, tolerance);
   ScanCustomSupportResistance(rates, copied, tolerance);
   PriceZone custom_support = CustomSRZone(1, tolerance);
   PriceZone custom_resistance = CustomSRZone(-1, tolerance);
   if(custom_support.valid && (!support.valid || MathAbs(close1 - ((custom_support.low + custom_support.high) * 0.5)) < MathAbs(close1 - ((support.low + support.high) * 0.5))))
      support = custom_support;
   if(custom_resistance.valid && (!resistance.valid || MathAbs(close1 - ((custom_resistance.low + custom_resistance.high) * 0.5)) < MathAbs(close1 - ((resistance.low + resistance.high) * 0.5))))
      resistance = custom_resistance;

   double rsi1 = GetRSI(_Symbol, InpStructureTF, InpSRRSIPeriod, 1);
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);

   TradeSignal buy, sell;
   EmptySignal(buy);
   EmptySignal(sell);

   PriceZone empty_zone = PriceZoneEmpty();

   if(InpSR_EnableBounce)
   {
      if(support.valid && low1 <= support.high && close1 > support.low &&
         (IsBullishPinBar(rates[1]) || IsBullishEngulfing(rates, 1)) && rsi1 > 50.0 &&
         !IsSlowGrindApproach(rates, copied))
      {
         BuildSRSignal(1, "SR_Bounce", "support rejection with bullish candle confirmation", support, empty_zone, rates, copied, buy);
         buy.score += 10.0;
      }

      if(resistance.valid && high1 >= resistance.low && close1 < resistance.high &&
         (IsBearishPinBar(rates[1]) || IsBearishEngulfing(rates, 1)) && rsi1 < 50.0 &&
         !IsSlowGrindApproach(rates, copied))
      {
         BuildSRSignal(-1, "SR_Bounce", "resistance rejection with bearish candle confirmation", empty_zone, resistance, rates, copied, sell);
         sell.score += 10.0;
      }
   }

   if(InpSR_EnablePullbackRetest)
   {
      TradeSignal pullback;
      EvaluateSRPullback(rates, copied, support, resistance, tolerance, atr, pullback);
      MergeStrategySignal(pullback, buy, sell);
   }

   if(InpSR_EnableDirectBreakout)
   {
      TradeSignal breakout;
      EvaluateSRBreakout(rates, copied, support, resistance, tolerance, atr, breakout);
      MergeStrategySignal(breakout, buy, sell);
   }

   if(InpSR_EnableFalseBreakoutTrap)
   {
      TradeSignal trap;
      EvaluateSRTrap(rates, copied, support, resistance, trap);
      MergeStrategySignal(trap, buy, sell);
   }

   if(InpSR_EnableChannelTrading)
   {
      TradeSignal channel;
      EvaluateSRChannel(rates, copied, tolerance, channel);
      MergeStrategySignal(channel, buy, sell);
   }

   if(InpSR_EnableFirstyMethod)
   {
      TradeSignal firsty;
      EvaluateFirstyTrade(rates, copied, support, resistance, tolerance, firsty);
      MergeStrategySignal(firsty, buy, sell);
   }

   if(buy.valid && (!sell.valid || buy.score >= sell.score))
      signal = buy;
   else if(sell.valid)
      signal = sell;
}

void BuildSRSignal(int direction,
                   string setup,
                   string reason,
                   const PriceZone &support,
                   const PriceZone &resistance,
                   const MqlRates &rates[],
                   int copied,
                   TradeSignal &out)
{
   EmptySignal(out);
   out.valid = true;
   out.direction = direction;
   out.strategy = "SRBounce";
   out.setup = setup;
   out.reason = "SR " + reason;
   out.score = 58.0;

   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), GetSRZoneTolerance() * 0.15);
   PriceZone sd_zone = PriceZoneEmpty();
   bool has_sd = FindSupplyDemandConfluence(direction, entry, support, resistance, sd_zone);
   if(InpEnableSupplyDemandZones && !has_sd)
   {
      out.valid = false;
      return;
   }

   if(has_sd)
   {
      out.score = ClampDouble(out.score + InpSDConfluenceBonus + sd_zone.strength * 2.0, 0.0, 100.0);
      out.setup = out.setup + "_SD";
      out.reason = out.reason + " with " + sd_zone.label + " confluence";
   }

   if(direction == 1)
   {
      double base_sl = has_sd ? sd_zone.low : (support.valid ? support.low : rates[1].low);
      out.sl = NormalizePrice(base_sl - buffer);
      double sd_target = OpposingSupplyDemandTarget(1, entry);
      if(InpSRUseNextZoneForTP && resistance.valid && resistance.low > entry)
         out.tp = NormalizePrice((sd_target > entry) ? MathMin(resistance.low, sd_target) : resistance.low);
      else if(sd_target > entry)
         out.tp = NormalizePrice(sd_target);
      else
         out.tp = NormalizePrice(entry + MathAbs(entry - out.sl) * InpDefaultRiskReward);
   }
   else
   {
      double base_sl = has_sd ? sd_zone.high : (resistance.valid ? resistance.high : rates[1].high);
      out.sl = NormalizePrice(base_sl + buffer);
      double sd_target = OpposingSupplyDemandTarget(-1, entry);
      if(InpSRUseNextZoneForTP && support.valid && support.high < entry)
         out.tp = NormalizePrice((sd_target > 0.0 && sd_target < entry) ? MathMax(support.high, sd_target) : support.high);
      else if(sd_target > 0.0 && sd_target < entry)
         out.tp = NormalizePrice(sd_target);
      else
         out.tp = NormalizePrice(entry - MathAbs(out.sl - entry) * InpDefaultRiskReward);
   }
}

void EvaluateSRPullback(const MqlRates &rates[],
                        int copied,
                        const PriceZone &support,
                        const PriceZone &resistance,
                        double tolerance,
                        double atr,
                        TradeSignal &signal)
{
   EmptySignal(signal);
   if(copied < 10 || atr <= 0.0)
      return;

   int confirm_bars = MathMax(1, InpSRBreakoutConfirmBars);
   bool broke_resistance = resistance.valid && ConsecutiveClosesBeyond(rates, copied, resistance.high + tolerance * 0.15, confirm_bars, 1);
   bool broke_support = support.valid && ConsecutiveClosesBeyond(rates, copied, support.low - tolerance * 0.15, confirm_bars, -1);

   bool retest_resistance_as_support = broke_resistance && rates[1].low <= resistance.high + tolerance && rates[1].close > resistance.high;
   bool retest_support_as_resistance = broke_support && rates[1].high >= support.low - tolerance && rates[1].close < support.low;

   PriceZone empty_zone = PriceZoneEmpty();
   PriceZone role_buy = FindBrokenRetestedZone(rates, copied, 1, tolerance);
   PriceZone role_sell = FindBrokenRetestedZone(rates, copied, -1, tolerance);
   TradeSignal tmp;
   if(role_buy.valid && HasBullishCandlePatternOnTF(InpStructureTF) && !IsSlowGrindApproach(rates, copied))
   {
      BuildSRSignal(1, "SR_RoleReversalPullback", "broken resistance retested as new support", role_buy, empty_zone, rates, copied, tmp);
      tmp.score = 74.0;
      signal = tmp;
   }
   else if(role_sell.valid && HasBearishCandlePatternOnTF(InpStructureTF) && !IsSlowGrindApproach(rates, copied))
   {
      BuildSRSignal(-1, "SR_RoleReversalPullback", "broken support retested as new resistance", empty_zone, role_sell, rates, copied, tmp);
      tmp.score = 74.0;
      signal = tmp;
   }
   else if(retest_resistance_as_support && HasBullishCandlePatternOnTF(InpStructureTF))
   {
      BuildSRSignal(1, "SR_RoleReversalPullback", "broken resistance retested as support", resistance, empty_zone, rates, copied, tmp);
      tmp.score = 70.0;
      signal = tmp;
   }
   else if(retest_support_as_resistance && HasBearishCandlePatternOnTF(InpStructureTF))
   {
      BuildSRSignal(-1, "SR_RoleReversalPullback", "broken support retested as resistance", empty_zone, support, rates, copied, tmp);
      tmp.score = 70.0;
      signal = tmp;
   }
}

void EvaluateSRBreakout(const MqlRates &rates[],
                        int copied,
                        const PriceZone &support,
                        const PriceZone &resistance,
                        double tolerance,
                        double atr,
                        TradeSignal &signal)
{
   EmptySignal(signal);
   if(copied < 10 || atr <= 0.0)
      return;

   double threshold = MathMax(tolerance * 0.20, atr * InpSRBreakoutThresholdATR);
   bool strong_body = BodyRatio(rates[1]) >= 0.50;
   PriceZone empty_zone = PriceZoneEmpty();
   TradeSignal tmp;

   if(resistance.valid && rates[1].close > resistance.high + threshold && strong_body &&
      ConsecutiveClosesBeyond(rates, copied, resistance.high + threshold, MathMax(1, InpSRBreakoutConfirmBars), 1))
   {
      BuildSRSignal(1, "SR_DirectBreakout", "confirmed direct breakout above resistance", resistance, empty_zone, rates, copied, tmp);
      tmp.score = 69.0;
      signal = tmp;
   }
   else if(support.valid && rates[1].close < support.low - threshold && strong_body &&
           ConsecutiveClosesBeyond(rates, copied, support.low - threshold, MathMax(1, InpSRBreakoutConfirmBars), -1))
   {
      BuildSRSignal(-1, "SR_DirectBreakout", "confirmed direct breakout below support", empty_zone, support, rates, copied, tmp);
      tmp.score = 69.0;
      signal = tmp;
   }
}

void EvaluateSRTrap(const MqlRates &rates[],
                    int copied,
                    const PriceZone &support,
                    const PriceZone &resistance,
                    TradeSignal &signal)
{
   EmptySignal(signal);
   PriceZone empty_zone = PriceZoneEmpty();
   TradeSignal tmp;

   if(support.valid && rates[1].low < support.low && rates[1].close > support.high &&
      (IsBullishPinBar(rates[1]) || IsBullishEngulfing(rates, 1)))
   {
      BuildSRSignal(1, "SR_FalseBreakoutTrap", "sell-side false break snapped back above support", support, empty_zone, rates, copied, tmp);
      tmp.score = 76.0;
      signal = tmp;
   }
   else if(resistance.valid && rates[1].high > resistance.high && rates[1].close < resistance.low &&
           (IsBearishPinBar(rates[1]) || IsBearishEngulfing(rates, 1)))
   {
      BuildSRSignal(-1, "SR_FalseBreakoutTrap", "buy-side false break snapped back below resistance", empty_zone, resistance, rates, copied, tmp);
      tmp.score = 76.0;
      signal = tmp;
   }
}

// V6.10: the current touch must be at least the fourth distinct touch of
// the projected channel line (two anchor swings + first retest + this
// second retest) before a channel-boundary trade is allowed.
void EvaluateSRChannel(const MqlRates &rates[], int copied, double tolerance, TradeSignal &signal)
{
   EmptySignal(signal);

   int low_a = -1, low_b = -1;
   int high_a = -1, high_b = -1;
   FindLastTwoSwingIndexes(rates, copied, InpStructureSwingDepth, 1, low_a, low_b);
   FindLastTwoSwingIndexes(rates, copied, InpStructureSwingDepth, -1, high_a, high_b);
   if(low_a < 0 || low_b < 0 || high_a < 0 || high_b < 0)
      return;

   double lower_now = ProjectLine(rates[low_b].time, rates[low_b].low, rates[low_a].time, rates[low_a].low, rates[1].time);
   double upper_now = ProjectLine(rates[high_b].time, rates[high_b].high, rates[high_a].time, rates[high_a].high, rates[1].time);

   bool rising_channel = rates[low_a].low > rates[low_b].low && rates[high_a].high > rates[high_b].high;
   bool falling_channel = rates[low_a].low < rates[low_b].low && rates[high_a].high < rates[high_b].high;

   int required_touches = InpRequireSecondRetest ? 4 : 2;

   TradeSignal tmp;
   if(rising_channel && rates[1].low <= lower_now + tolerance && rates[1].close > lower_now &&
      HasBullishCandlePatternOnTF(InpStructureTF))
   {
      int line_touches = CountTrendlineTouches(rates, copied, rates[low_b].time, rates[low_b].low,
                                               rates[low_a].time, rates[low_a].low, 1, tolerance);
      if(line_touches >= required_touches)
      {
         PriceZone lower = ZoneFromPrices(1, lower_now - tolerance, lower_now + tolerance, "SR Channel Support");
         PriceZone upper = ZoneFromPrices(-1, upper_now - tolerance, upper_now + tolerance, "SR Channel Resistance");
         BuildSRSignal(1, "SR_ChannelBoundary", "rising channel lower boundary second-retest rejection", lower, upper, rates, copied, tmp);
         tmp.score = 65.0 + MathMin(6.0, (line_touches - required_touches) * 2.0);
         signal = tmp;
      }
   }
   else if(falling_channel && rates[1].high >= upper_now - tolerance && rates[1].close < upper_now &&
           HasBearishCandlePatternOnTF(InpStructureTF))
   {
      int line_touches = CountTrendlineTouches(rates, copied, rates[high_b].time, rates[high_b].high,
                                               rates[high_a].time, rates[high_a].high, -1, tolerance);
      if(line_touches >= required_touches)
      {
         PriceZone lower = ZoneFromPrices(1, lower_now - tolerance, lower_now + tolerance, "SR Channel Support");
         PriceZone upper = ZoneFromPrices(-1, upper_now - tolerance, upper_now + tolerance, "SR Channel Resistance");
         BuildSRSignal(-1, "SR_ChannelBoundary", "falling channel upper boundary second-retest rejection", lower, upper, rates, copied, tmp);
         tmp.score = 65.0 + MathMin(6.0, (line_touches - required_touches) * 2.0);
         signal = tmp;
      }
   }
}

void EvaluateFirstyTrade(const MqlRates &rates[],
                         int copied,
                         const PriceZone &support,
                         const PriceZone &resistance,
                         double tolerance,
                         TradeSignal &signal)
{
   EmptySignal(signal);

   double ema60 = GetMA(_Symbol, InpStructureTF, 60, MODE_EMA, 1);
   double ema150 = GetMA(_Symbol, InpStructureTF, 150, MODE_EMA, 1);
   double ema365 = GetMA(_Symbol, InpStructureTF, 365, MODE_EMA, 1);
   if(ema60 == 0.0 || ema150 == 0.0 || ema365 == 0.0)
      return;

   double spread = MathAbs(ema60 - ema150) + MathAbs(ema150 - ema365);
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0 || spread < atr * 0.60)
      return;

   bool bull_stack = ema60 > ema150 && ema150 > ema365;
   bool bear_stack = ema60 < ema150 && ema150 < ema365;
   bool near_fast_ema = MathAbs(rates[1].close - ema60) <= tolerance || MathAbs(rates[1].low - ema60) <= tolerance || MathAbs(rates[1].high - ema60) <= tolerance;

   PriceZone empty_zone = PriceZoneEmpty();
   TradeSignal tmp;
   if(bull_stack && near_fast_ema && support.valid && rates[1].low <= support.high + tolerance && rates[1].close > ema60)
   {
      BuildSRSignal(1, "SR_FirstyPullback", "Firsty trend pullback into EMA60 and broken SR zone", support, empty_zone, rates, copied, tmp);
      tmp.score = 73.0;
      signal = tmp;
   }
   else if(bear_stack && near_fast_ema && resistance.valid && rates[1].high >= resistance.low - tolerance && rates[1].close < ema60)
   {
      BuildSRSignal(-1, "SR_FirstyPullback", "Firsty trend pullback into EMA60 and broken SR zone", empty_zone, resistance, rates, copied, tmp);
      tmp.score = 73.0;
      signal = tmp;
   }
}

//+------------------------------------------------------------------+
//| TrendFollowing                                                   |
//+------------------------------------------------------------------+
void EvaluateTrendFollowingSignal(TradeSignal &signal)
{
   EmptySignal(signal);
   TradeSignal trend_breaker, ma_momentum;
   EmptySignal(trend_breaker);
   EmptySignal(ma_momentum);
   EvaluateTrendBreaker(trend_breaker);
   EvaluateMAMomentumTrend(ma_momentum);

   if(trend_breaker.valid && (!ma_momentum.valid || trend_breaker.score >= ma_momentum.score))
      signal = trend_breaker;
   else if(ma_momentum.valid)
      signal = ma_momentum;

   ApplySupplyDemandConfluenceToSignal(signal, false);
}

void EvaluateTrendBreaker(TradeSignal &signal)
{
   EmptySignal(signal);

   MqlRates exec[];
   ArraySetAsSeries(exec, true);
   int copied = CopyRates(_Symbol, InpTrendExecutionTF, 0, 100, exec);
   if(copied < InpTrendBreakConfirmCandles + InpTrendTSMOMLookback + 5)
      return;

   TrendLine desc_h1, desc_h4, asc_h1, asc_h4;
   bool has_desc_h1 = BuildThreePointTrendLine(InpTrendHigherTF2, -1, desc_h1);
   bool has_desc_h4 = BuildThreePointTrendLine(InpTrendHigherTF1, -1, desc_h4);
   bool has_asc_h1 = BuildThreePointTrendLine(InpTrendHigherTF2, 1, asc_h1);
   bool has_asc_h4 = BuildThreePointTrendLine(InpTrendHigherTF1, 1, asc_h4);

   double line_buy = 0.0;
   bool buy_line_ok = false;
   if(has_desc_h1)
   {
      line_buy = ProjectTrendLine(desc_h1, exec[1].time);
      buy_line_ok = true;
   }
   if(has_desc_h4)
   {
      double h4_line = ProjectTrendLine(desc_h4, exec[1].time);
      line_buy = buy_line_ok ? MathMax(line_buy, h4_line) : h4_line;
      buy_line_ok = true;
   }

   double line_sell = 0.0;
   bool sell_line_ok = false;
   if(has_asc_h1)
   {
      line_sell = ProjectTrendLine(asc_h1, exec[1].time);
      sell_line_ok = true;
   }
   if(has_asc_h4)
   {
      double h4_line = ProjectTrendLine(asc_h4, exec[1].time);
      line_sell = sell_line_ok ? MathMin(line_sell, h4_line) : h4_line;
      sell_line_ok = true;
   }

   bool ma_cross_up = CrossedMA(InpTrendExecutionTF, InpTrendSMAFast, MODE_SMA, InpTrendEMAFast, MODE_EMA, 1);
   bool ma_cross_down = CrossedMA(InpTrendExecutionTF, InpTrendSMAFast, MODE_SMA, InpTrendEMAFast, MODE_EMA, -1);
   bool macd_cross_up = MACDCrossed(InpTrendExecutionTF, 1);
   bool macd_cross_down = MACDCrossed(InpTrendExecutionTF, -1);
   bool tsmom_up = exec[1].close > exec[1 + InpTrendTSMOMLookback].close;
   bool tsmom_down = exec[1].close < exec[1 + InpTrendTSMOMLookback].close;

   bool three_up = buy_line_ok && ThreeCandleBreak(exec, copied, line_buy, 1);
   bool three_down = sell_line_ok && ThreeCandleBreak(exec, copied, line_sell, -1);

   if(three_up && ma_cross_up && macd_cross_up && tsmom_up)
   {
      double atr = GetATR(_Symbol, InpTrendExecutionTF, InpTrendATRPeriod, 1);
      double low = LowestLow(_Symbol, InpTrendExecutionTF, 20, 1);
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      signal.valid = true;
      signal.direction = 1;
      signal.strategy = "TrendFollowing";
      signal.setup = "TrendBreaker_3CandleRule";
      signal.reason = "Trend breaker buy: 3 M15 closes above H1/H4 descending trendline with SMA/EMA and MACD confirmation";
      signal.score = 78.0;
      signal.sl = NormalizePrice(low - atr * 0.50);
      signal.tp = NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward);
   }
   else if(three_down && ma_cross_down && macd_cross_down && tsmom_down)
   {
      double atr = GetATR(_Symbol, InpTrendExecutionTF, InpTrendATRPeriod, 1);
      double high = HighestHigh(_Symbol, InpTrendExecutionTF, 20, 1);
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      signal.valid = true;
      signal.direction = -1;
      signal.strategy = "TrendFollowing";
      signal.setup = "TrendBreaker_3CandleRule";
      signal.reason = "Trend breaker sell: 3 M15 closes below H1/H4 ascending trendline with SMA/EMA and MACD confirmation";
      signal.score = 78.0;
      signal.sl = NormalizePrice(high + atr * 0.50);
      signal.tp = NormalizePrice(entry - MathAbs(signal.sl - entry) * InpDefaultRiskReward);
   }
}

void EvaluateMAMomentumTrend(TradeSignal &signal)
{
   EmptySignal(signal);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpTrendExecutionTF, 0, InpTrendTSMOMLookback + 10, rates);
   if(copied < InpTrendTSMOMLookback + 5)
      return;

   double ema50 = GetMA(_Symbol, InpTrendExecutionTF, InpTrendEMA50, MODE_EMA, 1);
   double ema200 = GetMA(_Symbol, InpTrendExecutionTF, InpTrendEMA200, MODE_EMA, 1);
   double rsi1 = GetRSI(_Symbol, InpTrendExecutionTF, InpTrendRSIPeriod, 1);
   double rsi2 = GetRSI(_Symbol, InpTrendExecutionTF, InpTrendRSIPeriod, 2);
   double macd_main_1, macd_signal_1, macd_main_2, macd_signal_2;
   GetMACD(_Symbol, InpTrendExecutionTF, 1, macd_main_1, macd_signal_1);
   GetMACD(_Symbol, InpTrendExecutionTF, 2, macd_main_2, macd_signal_2);

   bool hist_expanding_up = (macd_main_1 - macd_signal_1) > (macd_main_2 - macd_signal_2);
   bool hist_expanding_down = (macd_main_1 - macd_signal_1) < (macd_main_2 - macd_signal_2);
   bool tsmom_up = rates[1].close > rates[1 + InpTrendTSMOMLookback].close;
   bool tsmom_down = rates[1].close < rates[1 + InpTrendTSMOMLookback].close;

   if(ema50 > ema200 && rates[1].low <= ema50 && rates[1].close > ema50 &&
      ((rsi2 < 30.0 && rsi1 > 30.0) || rsi1 > 50.0) &&
      macd_main_1 > macd_signal_1 && hist_expanding_up && tsmom_up)
   {
      double atr = GetATR(_Symbol, InpTrendExecutionTF, InpTrendATRPeriod, 1);
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      signal.valid = true;
      signal.direction = 1;
      signal.strategy = "TrendFollowing";
      signal.setup = "MA_TSMOM_Pullback";
      signal.reason = "Trend buy: EMA50 above EMA200, pullback to EMA50, RSI/MACD rebound, and positive time-series momentum";
      signal.score = 72.0;
      signal.sl = NormalizePrice(MathMin(rates[1].low, ema50) - MathMax(atr * 0.70, InpStopLossBufferPoints * _Point));
      signal.tp = NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward);
   }
   else if(ema50 < ema200 && rates[1].high >= ema50 && rates[1].close < ema50 &&
           ((rsi2 > 70.0 && rsi1 < 70.0) || rsi1 < 50.0) &&
           macd_main_1 < macd_signal_1 && hist_expanding_down && tsmom_down)
   {
      double atr = GetATR(_Symbol, InpTrendExecutionTF, InpTrendATRPeriod, 1);
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      signal.valid = true;
      signal.direction = -1;
      signal.strategy = "TrendFollowing";
      signal.setup = "MA_TSMOM_Pullback";
      signal.reason = "Trend sell: EMA50 below EMA200, pullback to EMA50, RSI/MACD rejection, and negative time-series momentum";
      signal.score = 72.0;
      signal.sl = NormalizePrice(MathMax(rates[1].high, ema50) + MathMax(atr * 0.70, InpStopLossBufferPoints * _Point));
      signal.tp = NormalizePrice(entry - MathAbs(signal.sl - entry) * InpDefaultRiskReward);
   }
}

//+------------------------------------------------------------------+
//| Trading and risk                                                 |
//+------------------------------------------------------------------+
bool OpenSignal(TradeSignal &signal)
{
   ENUM_ORDER_TYPE order_type = (signal.direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entry = (signal.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = signal.sl;
   double tp = signal.tp;

   if(sl <= 0.0 || tp <= 0.0)
      BuildFallbackStops(signal.direction, entry, sl, tp);

   // V6.35: room to breathe - the structural stop may be widened out to the
   // ATR floor, never tightened. Position sizing shrinks to compensate.
   ApplyMinimumStopDistance(signal.direction, entry, sl);

   if(!ApplyStopDistanceCaps(signal, entry, sl, tp))
   {
      LogJournal("ORDER_REJECTED", 0, _Symbol, DirectionToText(signal.direction), 0.0, entry, 0.0, sl, tp,
                 signal.strategy, "NO_TRADE", 0.0, g_last_risk_reject_reason,
                 signal.reason, "Trade skipped because stop distance exceeded the configured cap", signal.setup);
      Print(g_last_risk_reject_reason);
      return false;
   }
   string stop_policy_note = g_last_risk_reject_reason;

   bool boundary_target_setup = StringFind(signal.setup, "RANGE_Cycle") >= 0 ||
                                StringFind(signal.setup, "ROTATION_") >= 0;
   if(!boundary_target_setup)
   {
      ApplyHistoricalM15Target(signal.direction, entry, sl, tp);
      EnsureMinimumRiskReward(signal.direction, entry, sl, tp);
   }
   else
   {
      // V6.30/V6.31: range-cycle and rotation exits live at a fixed % of the
      // way to the opposite boundary and are never stretched beyond it.
      double boundary_min_rr = (StringFind(signal.setup, "ROTATION_") >= 0)
                               ? MathMax(0.5, InpRotationMinRR)
                               : MathMax(0.5, InpRangeMinRR);
      double range_risk = MathAbs(entry - sl);
      double range_reward = MathAbs(tp - entry);
      if(range_risk <= 0.0 || range_reward / range_risk < boundary_min_rr)
      {
         LogJournal("ORDER_REJECTED", 0, _Symbol, DirectionToText(signal.direction), 0.0, entry, 0.0, sl, tp,
                    signal.strategy, "NO_TRADE", 0.0, "Boundary reward below the minimum reward:risk",
                    signal.reason, "Boundary stop too wide relative to the travel distance", signal.setup);
         return false;
      }
   }
   EnsureValidStops(signal.direction, entry, sl, tp);

   g_rotation_sizing = StringFind(signal.setup, "ROTATION_") >= 0;
   double volume = CalculateVolumeForRisk(order_type, entry, sl);
   if(volume <= 0.0)
   {
      LogJournal("ORDER_REJECTED", 0, _Symbol, DirectionToText(signal.direction), 0.0, entry, 0.0, sl, tp,
                 signal.strategy, "NO_TRADE", 0.0, "Volume calculation failed",
                 signal.reason, g_last_risk_reject_reason == "" ? "Reduce risk or check symbol tick value" : g_last_risk_reject_reason, signal.setup);
      return false;
   }

   string comment = BuildTradeComment(signal.strategy);
   bool ok = trade.PositionOpen(_Symbol, order_type, volume, entry, sl, tp, comment);
   if(!ok)
   {
      string fail = "Order failed. Retcode " + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription();
      LogJournal("ORDER_FAILED", 0, _Symbol, DirectionToText(signal.direction), volume, entry, 0.0, sl, tp,
                 signal.strategy, "FAILED", 0.0, fail, signal.reason,
                 "Check stops, margin, market mode, or broker limits", signal.setup);
      Print(fail);
      return false;
   }

   // V6.10: a successful pilot entry moves the pilot state to "awaiting
   // trend confirmation". Confirmation comes from open profit reaching
   // InpPilotConfirmProfitRR or from the pilot closing in profit.
   if(g_last_pilot_lot_used)
      SetPilotStage(1);

   string sizing_note = g_last_pilot_lot_used ?
                        "Pilot minimum-lot entry; full risk sizing unlocks after trend confirmation" :
                        (g_last_minimum_lot_compatibility_used ?
                         "Broker minimum lot accepted within the configured actual-risk cap" :
                         "Initial SL/TP normalized; trailing and journal memory active");

   ulong deal = trade.ResultDeal();
   ulong order = trade.ResultOrder();
   ulong ticket = (deal > 0) ? deal : order;
   LogJournal("OPEN", ticket, _Symbol, DirectionToText(signal.direction), volume, entry, 0.0, sl, tp,
              signal.strategy, "OPEN", 0.0, AppendToken(signal.reason, stop_policy_note),
              "Trade opened because this was the highest-scoring non-conflicting setup",
              sizing_note, signal.setup);

   StorePositionRiskState(MathAbs(entry - sl), tp);

   return true;
}

// V6.10: pilot minimum-lot sizing, a broker-verified loss-per-lot
// cross-check, an absolute lot ceiling, and a final risk-overrun check.
double CalculateVolumeForRisk(ENUM_ORDER_TYPE order_type, double entry, double sl)
{
   g_last_risk_reject_reason = "";
   g_last_risk_cash = CalculateAllowedRiskCash();
   g_last_loss_per_lot = 0.0;
   g_last_minimum_lot_compatibility_used = false;
   g_last_pilot_lot_used = false;

   double risk_cash = g_last_risk_cash;
   // V6.31: counter-trend rotation trades run at a reduced risk budget.
   if(g_rotation_sizing)
   {
      risk_cash *= ClampDouble(InpRotationRiskFactor, 0.10, 1.00);
      g_last_risk_cash = risk_cash;
      g_rotation_sizing = false;
   }
   double price_distance = MathAbs(entry - sl);
   if(price_distance <= 0.0 || risk_cash <= 0.0)
   {
      g_last_risk_reject_reason = "Risk budget is zero or stop distance is invalid";
      return 0.0;
   }

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_value <= 0.0 || tick_size <= 0.0)
   {
      g_last_risk_reject_reason = "Symbol tick value or tick size is unavailable";
      return 0.0;
   }

   double loss_per_lot = (price_distance / tick_size) * tick_value;

   // V6.10 safety: cross-check with the broker's own profit calculator.
   // If the terminal's tick data is stale or wrong at startup, the larger
   // of the two estimates is used, which prevents oversized volumes.
   double calc_profit = 0.0;
   if(OrderCalcProfit(order_type, _Symbol, 1.0, entry, sl, calc_profit))
   {
      double broker_loss_per_lot = MathAbs(calc_profit);
      if(broker_loss_per_lot > 0.0)
         loss_per_lot = MathMax(loss_per_lot, broker_loss_per_lot);
   }

   g_last_loss_per_lot = loss_per_lot;
   if(loss_per_lot <= 0.0)
   {
      g_last_risk_reject_reason = "Loss per lot could not be calculated";
      return 0.0;
   }

   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = 0.0;
   double min_lot_risk = loss_per_lot * min_vol;

   // ---- V6.10 pilot first trade -------------------------------------
   // The opening trade of a fresh trend always uses the broker minimum
   // lot, provided its true risk stays inside the pilot cap. Full
   // risk-based sizing unlocks only after the trend is confirmed.
   if(InpUsePilotFirstTrade && PilotStage() == 0)
   {
      double pilot_risk_percent = (equity > 0.0) ? min_lot_risk * 100.0 / equity : 1.0e100;
      if(pilot_risk_percent > MathMax(0.01, InpPilotMaxActualRiskPercent))
      {
         g_last_risk_reject_reason = "Pilot minimum lot risks " + DoubleToString(pilot_risk_percent, 2) +
                                     "% of equity, above the pilot cap of " +
                                     DoubleToString(InpPilotMaxActualRiskPercent, 2) + "%";
         return 0.0;
      }
      if(OrderCalcMargin(order_type, _Symbol, min_vol, entry, margin) && margin <= free_margin * 0.90)
      {
         g_last_pilot_lot_used = true;
         return NormalizeVolume(min_vol);
      }
      g_last_risk_reject_reason = "Not enough free margin for the pilot minimum lot";
      return 0.0;
   }

   bool min_lot_compatible = IsMinimumLotRiskCompatible(min_lot_risk);
   if(InpSkipTradeWhenMinLotTooRisky && min_lot_risk > risk_cash && !min_lot_compatible)
   {
      g_last_risk_reject_reason = "Risk too high: minimum lot risks " + DoubleToString(min_lot_risk, 2) +
                                  " while allowed risk is " + DoubleToString(risk_cash, 2) +
                                  " and exceeds the minimum-lot actual-risk cap";
      return 0.0;
   }

   if(InpUseFixedLot)
   {
      double fixed_volume = NormalizeVolume(InpFixedLot);
      if(InpMaxLotAbsolute > 0.0)
         fixed_volume = MathMin(fixed_volume, NormalizeVolume(InpMaxLotAbsolute));
      double fixed_risk = fixed_volume * loss_per_lot;
      bool fixed_is_minimum_lot = fixed_volume <= min_vol + MathMax(step, min_vol) * 0.5;
      bool fixed_lot_compatible = fixed_is_minimum_lot && IsMinimumLotRiskCompatible(fixed_risk);
      if(InpSkipTradeWhenMinLotTooRisky && fixed_risk > risk_cash && !fixed_lot_compatible)
      {
         g_last_risk_reject_reason = "Fixed lot risks " + DoubleToString(fixed_risk, 2) +
                                     " while allowed risk is " + DoubleToString(risk_cash, 2) +
                                     " and exceeds the actual-risk cap";
         return 0.0;
      }
      if(fixed_risk > risk_cash && fixed_lot_compatible)
         g_last_minimum_lot_compatibility_used = true;
      if(OrderCalcMargin(order_type, _Symbol, fixed_volume, entry, margin) && margin <= free_margin * 0.90)
         return fixed_volume;
      g_last_risk_reject_reason = "Not enough free margin for fixed lot";
      return 0.0;
   }

   double raw_volume = risk_cash / loss_per_lot;
   if(raw_volume < min_vol)
   {
      if(!min_lot_compatible)
      {
         g_last_risk_reject_reason = "Calculated volume is below broker minimum and the minimum lot exceeds the actual-risk cap";
         return 0.0;
      }
      // Use the broker's smallest possible size only after the actual loss at
      // that size has passed the per-symbol cap above.
      raw_volume = min_vol;
      g_last_minimum_lot_compatibility_used = true;
   }

   double volume = NormalizeVolumeDown(raw_volume);

   // V6.10 safety: an absolute ceiling that no signal can override.
   if(InpMaxLotAbsolute > 0.0)
      volume = MathMin(volume, NormalizeVolumeDown(InpMaxLotAbsolute));

   while(volume >= min_vol)
   {
      // V6.10 safety: the final sized risk must remain inside the budget
      // (small tolerance for lot-step rounding). Only a sanctioned
      // minimum-lot compatibility entry may exceed it.
      double sized_risk = volume * loss_per_lot;
      bool risk_ok = sized_risk <= risk_cash * MathMax(1.0, InpMaxRiskOverrunFactor) ||
                     (volume <= min_vol + step * 0.5 && min_lot_compatible);
      if(risk_ok && OrderCalcMargin(order_type, _Symbol, volume, entry, margin) && margin <= free_margin * 0.90)
         return NormalizeVolume(volume);
      volume = NormalizeVolumeDown(volume - step);
   }

   g_last_risk_reject_reason = "Not enough free margin or risk headroom after sizing";
   return 0.0;
}

void BuildFallbackStops(int direction, double entry, double &sl, double &tp)
{
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      atr = MathMax(100.0 * _Point, InpSRManualSLPoints * _Point);

   if(direction == 1)
   {
      sl = NormalizePrice(entry - atr * 1.5);
      tp = NormalizePrice(entry + atr * 1.5 * InpDefaultRiskReward);
   }
   else
   {
      sl = NormalizePrice(entry + atr * 1.5);
      tp = NormalizePrice(entry - atr * 1.5 * InpDefaultRiskReward);
   }
}

void EnsureMinimumRiskReward(int direction, double entry, double &sl, double &tp)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return;

   double reward = MathAbs(tp - entry);
   double min_reward = risk * MathMax(InpMinRiskReward, 1.0);
   if(reward >= min_reward)
      return;

   if(direction == 1)
      tp = NormalizePrice(entry + min_reward);
   else
      tp = NormalizePrice(entry - min_reward);
}

void EnsureValidStops(int direction, double entry, double &sl, double &tp)
{
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   // V6.21: pad by the freeze level and the live spread as well - this removes
   // the "invalid stops" (retcode 10016) order failures seen in the journal.
   double min_dist = MathMax((double)MathMax(stops_level, freeze_level) * _Point + spread, 2.0 * _Point);

   if(direction == 1)
   {
      if(entry - sl < min_dist)
         sl = entry - min_dist;
      if(tp - entry < min_dist)
         tp = entry + min_dist * MathMax(InpMinRiskReward, 2.0);
   }
   else
   {
      if(sl - entry < min_dist)
         sl = entry + min_dist;
      if(entry - tp < min_dist)
         tp = entry - min_dist * MathMax(InpMinRiskReward, 2.0);
   }

   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
}

//+------------------------------------------------------------------+
//| Adaptive trade management                                        |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      int direction = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double current = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      double volume = PositionGetDouble(POSITION_VOLUME);

      double atr = GetATR(_Symbol, InpTrendExecutionTF, InpTrendATRPeriod, 1);
      double stored_risk = GetStoredPositionRisk(ticket);
      double risk = (stored_risk > 0.0) ? stored_risk : MathAbs(open_price - sl);
      if(risk <= 0.0)
         risk = atr * 1.5;
      if(risk <= 0.0)
         continue;

      double open_profit_distance = (current - open_price) * direction;
      double rr = open_profit_distance / risk;
      if(atr <= 0.0)
         atr = risk;

      double new_sl = sl;
      double new_tp = tp;
      bool modify = false;
      bool staged_targets = StagedTargetsUsable(ticket);

      if(!staged_targets && InpUsePartialTargets && rr >= MathMax(0.10, InpPartialCloseAtRR) && !PositionPartialTaken(ticket))
      {
         if(ClosePartialPosition(ticket, volume))
         {
            MarkPositionPartialTaken(ticket);
            LogJournal("MANAGE", ticket, _Symbol, DirectionToText(direction), volume,
                       open_price, current, sl, tp, ExpandStrategyFromComment(PositionGetString(POSITION_COMMENT)),
                       "PARTIAL_PROFIT", PositionGetDouble(POSITION_PROFIT), "partial target reached",
                       "EA locked a planned partial profit at " + DoubleToString(rr, 2) + "R",
                       "Remainder is managed with break-even and trailing protection", MemorySummary());

            if(InpMoveSLToBEAfterPartial)
            {
               double partial_be = open_price + direction * BreakEvenCostBuffer(atr);
               if(StopImproves(direction, new_sl, partial_be))
               {
                  new_sl = NormalizePrice(partial_be);
                  modify = true;
               }
            }
         }
      }

      if(InpUseBreakEven && rr >= InpBreakEvenAtRR)
      {
         double be_buffer = BreakEvenCostBuffer(atr);
         double be = open_price + direction * be_buffer;
         bool profit_covers_costs = open_profit_distance >= risk * InpBreakEvenAtRR + be_buffer;
         if(StopImproves(direction, new_sl, be))
         {
            if(profit_covers_costs)
            {
               new_sl = NormalizePrice(be);
               modify = true;
            }
         }
      }

      if(!staged_targets && InpUseATRTrailingStop && rr >= EffectiveTrailStartRR())
      {
         double raw_trail = current - direction * atr * EffectiveTrailATRMultiplier();
         double trail = GradualStopCandidate(direction, new_sl, raw_trail, atr);
         if(StopImproves(direction, new_sl, trail))
         {
            new_sl = NormalizePrice(trail);
            modify = true;
         }
      }

      if(!staged_targets && InpUseTrailingTakeProfit && tp > 0.0)
      {
         double distance_to_tp = (tp - current) * direction;
         if(distance_to_tp > 0.0 && distance_to_tp <= atr * InpTPExtendThresholdATR && MomentumStillFavorable(direction))
         {
            new_tp = NormalizePrice(tp + direction * atr * InpTPExtendATRMultiplier);
            modify = true;
         }
      }

      if(!staged_targets && InpUseMATrailingTP && tp > 0.0 && MomentumStillFavorable(direction))
      {
         double ema_tp = GetMA(_Symbol, InpTrendExecutionTF, MathMax(2, InpMATPPeriod), MODE_EMA, 1);
         if(ema_tp > 0.0)
         {
            double ma_band_tp = ema_tp + direction * atr * MathMax(0.10, InpMATPATRMultiplier);
            if(direction == 1 && ma_band_tp > new_tp && ma_band_tp > current)
            {
               new_tp = NormalizePrice(ma_band_tp);
               modify = true;
            }
            if(direction == -1 && ma_band_tp < new_tp && ma_band_tp < current)
            {
               new_tp = NormalizePrice(ma_band_tp);
               modify = true;
            }
         }
      }

      if(modify)
      {
         EnsureValidStops(direction, current, new_sl, new_tp);
         trade.PositionModify(ticket, new_sl, new_tp);
      }

      if(InpUseAdaptiveExit && rr >= EffectiveSoftExitMinimumRR())
      {
         int bars_open = iBarShift(_Symbol, InpEntryTF, open_time, false);
         bool held_long_enough = bars_open >= MathMax(0, InpAdaptiveExitMinHoldBars);
         bool held_too_long = (InpMaxTradeBars > 0 && bars_open >= InpMaxTradeBars);
         bool structure_invalidated = HasAdverseStructureInvalidation(direction);
         bool momentum_failing = InpExitOnMomentumFailure && MomentumFailing(direction);
         bool opposite_signal = false;

         if(InpCloseOnOppositeSignal)
         {
            TradeSignal combined;
            BuildCombinedSignal(combined);
            opposite_signal = combined.valid && combined.direction == -direction &&
                              combined.score >= InpMinimumSignalScore + 10.0;
         }

         bool exit_requires_structure = InpAdaptiveExitRequiresStructureBreak;
         bool confirmed_exit = (held_too_long || (held_long_enough && (momentum_failing || opposite_signal))) &&
                               (!exit_requires_structure || structure_invalidated);
         if(confirmed_exit)
         {
            string reason = held_too_long ? "adaptive time and structure exit" :
                            (momentum_failing ? "adaptive momentum and structure exit" :
                             "opposite high-score signal and structure exit");
            LogJournal("MANAGE", ticket, _Symbol, DirectionToText(direction), PositionGetDouble(POSITION_VOLUME),
                       open_price, current, new_sl, new_tp, ExpandStrategyFromComment(PositionGetString(POSITION_COMMENT)),
                       "PROFIT_PROTECT", PositionGetDouble(POSITION_PROFIT), reason,
                       "EA closed only after a confirmed M15 structural invalidation of a protected trade",
                       "Normal pullbacks are left to the structural SL and wider ATR trailing stop", MemorySummary());
            trade.PositionClose(ticket);
         }
      }
   }
}

bool StopImproves(int direction, double old_sl, double candidate)
{
   if(old_sl <= 0.0)
      return true;
   if(direction == 1)
      return candidate > old_sl + _Point;
   return candidate < old_sl - _Point;
}

bool MomentumStillFavorable(int direction)
{
   double ema50 = GetMA(_Symbol, InpTrendExecutionTF, InpTrendEMA50, MODE_EMA, 1);
   double ema200 = GetMA(_Symbol, InpTrendExecutionTF, InpTrendEMA200, MODE_EMA, 1);
   double rsi = GetRSI(_Symbol, InpTrendExecutionTF, InpTrendRSIPeriod, 1);
   double macd_main, macd_sig;
   GetMACD(_Symbol, InpTrendExecutionTF, 1, macd_main, macd_sig);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpTrendExecutionTF, 0, InpTrendTSMOMLookback + 5, rates);
   bool tsmom_ok = false;
   if(copied > InpTrendTSMOMLookback + 2)
      tsmom_ok = (direction == 1) ? (rates[1].close > rates[1 + InpTrendTSMOMLookback].close)
                                  : (rates[1].close < rates[1 + InpTrendTSMOMLookback].close);

   if(direction == 1)
      return ema50 >= ema200 && rsi >= 50.0 && macd_main >= macd_sig && tsmom_ok;
   return ema50 <= ema200 && rsi <= 50.0 && macd_main <= macd_sig && tsmom_ok;
}

bool MomentumFailing(int direction)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpTrendExecutionTF, 0, 5, rates);
   if(copied < 4)
      return false;

   double ema50_1 = GetMA(_Symbol, InpTrendExecutionTF, InpTrendEMA50, MODE_EMA, 1);
   double ema50_2 = GetMA(_Symbol, InpTrendExecutionTF, InpTrendEMA50, MODE_EMA, 2);
   double rsi = GetRSI(_Symbol, InpTrendExecutionTF, InpTrendRSIPeriod, 1);
   double macd_main, macd_sig;
   GetMACD(_Symbol, InpTrendExecutionTF, 1, macd_main, macd_sig);

   if(direction == 1)
      return (rates[1].close < ema50_1 && rates[2].close < ema50_2) &&
             rsi < 45.0 && macd_main < macd_sig;
   return (rates[1].close > ema50_1 && rates[2].close > ema50_2) &&
          rsi > 55.0 && macd_main > macd_sig;
}

bool HasAdverseStructureInvalidation(int direction)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpTrendExecutionTF, 0, 100, rates);
   int depth = MathMax(2, InpFractalDepth);
   if(copied < depth * 2 + 15)
      return false;

   int recent_high = -1, previous_high = -1;
   int recent_low = -1, previous_low = -1;
   if(direction == 1)
   {
      FindLastTwoSwingIndexes(rates, copied, depth, 1, recent_low, previous_low);
      if(recent_low < 0 || previous_low < 0)
         return false;
      // A long survives ordinary pullbacks; it exits only after two closed M15 bars break the protected swing low.
      return ConsecutiveClosesBeyond(rates, copied, rates[recent_low].low, 2, -1);
   }

   FindLastTwoSwingIndexes(rates, copied, depth, -1, recent_high, previous_high);
   if(recent_high < 0 || previous_high < 0)
      return false;
   // A short survives ordinary pullbacks; it exits only after two closed M15 bars break the protected swing high.
   return ConsecutiveClosesBeyond(rates, copied, rates[recent_high].high, 2, 1);
}

//+------------------------------------------------------------------+
//| Daily limits                                                     |
//+------------------------------------------------------------------+
void SetupDailyState()
{
   g_day_start_time = StartOfDay(TimeCurrent());
   g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_locked = false;
   g_daily_lock_reason = "";
}

void ResetDailyStateIfNeeded()
{
   datetime today = StartOfDay(TimeCurrent());
   if(today != g_day_start_time)
   {
      SetupDailyState();
      LogJournal("DAILY_RESET", 0, _Symbol, "", 0.0, 0.0, 0.0, 0.0, 0.0,
                 "All", "RESET", 0.0, "New trading day started",
                 "Daily profit and loss counters were reset",
                 "Journal memory remains active", MemorySummary());
   }
}

void CheckDailyLimits()
{
   double today_profit = GetTodayClosedProfit();
   if(InpDailyLimitsUseFloatingPL)
      today_profit += GetOpenProfitForMagic();

   double target_money = InpDailyProfitTargetMoney;
   double loss_money = InpDailyLossLimitMoney;

   if(InpDailyProfitTargetPercent > 0.0)
      target_money = MathMax(target_money, g_day_start_equity * InpDailyProfitTargetPercent / 100.0);
   if(InpDailyLossLimitPercent > 0.0)
      loss_money = MathMax(loss_money, g_day_start_equity * InpDailyLossLimitPercent / 100.0);

   bool just_locked = false;
   if(!g_daily_locked && target_money > 0.0 && today_profit >= target_money)
   {
      g_daily_locked = true;
      just_locked = true;
      g_daily_lock_reason = "Daily profit target reached";
   }

   if(!g_daily_locked && loss_money > 0.0 && today_profit <= -loss_money)
   {
      g_daily_locked = true;
      just_locked = true;
      g_daily_lock_reason = "Daily loss limit reached";
   }

   if(g_daily_locked)
   {
      if(just_locked)
      {
         LogJournal("DAILY_LOCK", 0, _Symbol, "", 0.0, 0.0, 0.0, 0.0, 0.0,
                    "All", "LOCKED", today_profit, g_daily_lock_reason,
                    "EA stopped opening new trades for the rest of the trading day",
                    "Daily limits can be changed in inputs", MemorySummary());
      }

      if(InpClosePositionsAtDailyLimit)
         CloseAllOurPositions();
   }
}

double GetTodayClosedProfit()
{
   double profit = 0.0;
   if(!HistorySelect(g_day_start_time, TimeCurrent()))
      return 0.0;

   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
         continue;
      profit += HistoryDealGetDouble(deal, DEAL_PROFIT)
              + HistoryDealGetDouble(deal, DEAL_SWAP)
              + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
   return profit;
}

double GetTotalClosedProfit()
{
   double profit = 0.0;
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
         continue;
      profit += HistoryDealGetDouble(deal, DEAL_PROFIT)
              + HistoryDealGetDouble(deal, DEAL_SWAP)
              + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
   return profit;
}

double GetOpenProfitForMagic()
{
   double profit = 0.0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      profit += PositionGetDouble(POSITION_PROFIT);
   }
   return profit;
}

void CloseAllOurPositions()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      trade.PositionClose(ticket);
   }

   // V6.34: a daily lock also clears our resting order-block limit orders.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong order_ticket = OrderGetTicket(i);
      if(order_ticket == 0)
         continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      trade.OrderDelete(order_ticket);
   }
}

//+------------------------------------------------------------------+
//| Journal and memory                                               |
//+------------------------------------------------------------------+
void EnsureJournalHeader()
{
   if(!InpUseTradingJournal)
      return;

   bool need_header = true;
   int read_handle = FileOpen(InpJournalFileName, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(read_handle != INVALID_HANDLE)
   {
      if(FileSize(read_handle) > 0)
         need_header = false;
      FileClose(read_handle);
   }

   int handle = FileOpen(InpJournalFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(handle == INVALID_HANDLE)
      return;

   FileSeek(handle, 0, SEEK_END);
   if(need_header)
   {
      FileWrite(handle,
                 "Time", "Event", "Ticket", "Symbol", "Direction", "Lot",
                 "OpenPrice", "ClosePrice", "SL", "TP", "Strategy", "Result",
                 "Profit", "Reason", "WhyWonOrLost", "AdjustmentMade", "BestStrategySetup",
                 "AccountBalance", "AccountEquity", "RiskPercent", "RiskCash",
                 "VolatilityRiskFactor", "LossPerLot", "StopDistancePoints", "StopRiskMoney",
                 "RewardDistancePoints", "PlannedRR", "SpreadPoints", "EntryATR",
                 "AverageEntryATR", "ATRStopMultiplier", "AgreeingStrategies", "RequiredStrategies",
                 "SupplyDemandZoneCount", "NearestDemandLow", "NearestDemandHigh", "NearestDemandLabel",
                 "NearestSupplyLow", "NearestSupplyHigh", "NearestSupplyLabel", "OpenMagicPL",
                 "DailyClosedPL", "TotalClosedPL", "MarketRegime");
   }
   FileClose(handle);
}

void LogJournal(string event_name,
                ulong ticket,
                string symbol,
                string direction,
                double lot,
                double open_price,
                double close_price,
                double sl,
                double tp,
                string strategy,
                string result_text,
                double profit,
                string reason,
                string why,
                string adjustment,
                string best_setup)
{
   if(!InpUseTradingJournal)
      return;

   int handle = FileOpen(InpJournalFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(handle == INVALID_HANDLE)
      return;

   FileSeek(handle, 0, SEEK_END);
   double stop_distance = MathAbs(open_price - sl);
   double reward_distance = MathAbs(tp - open_price);
   double stop_points = (stop_distance > 0.0) ? stop_distance / _Point : 0.0;
   double reward_points = (reward_distance > 0.0) ? reward_distance / _Point : 0.0;
   double planned_rr = (stop_distance > 0.0) ? reward_distance / stop_distance : 0.0;
   double stop_risk_money = (g_last_loss_per_lot > 0.0 && lot > 0.0) ? g_last_loss_per_lot * lot : 0.0;
   double entry_atr = GetATR(_Symbol, InpEntryTF, InpTrendATRPeriod, 1);
   double average_entry_atr = GetAverageATR(_Symbol, InpEntryTF, InpTrendATRPeriod, MathMax(20, InpVolatilityATRAvgBars), 1);
   PriceZone nearest_demand = PriceZoneEmpty();
   PriceZone nearest_supply = PriceZoneEmpty();
   FindNearestSupplyDemandZone(1, open_price, nearest_demand);
   FindNearestSupplyDemandZone(-1, open_price, nearest_supply);

   FileWrite(handle,
              TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
              CleanCSV(event_name),
             (string)ticket,
             CleanCSV(symbol),
             CleanCSV(direction),
             DoubleToString(lot, 2),
             DoubleToString(open_price, _Digits),
             DoubleToString(close_price, _Digits),
             DoubleToString(sl, _Digits),
             DoubleToString(tp, _Digits),
             CleanCSV(strategy),
             CleanCSV(result_text),
             DoubleToString(profit, 2),
              CleanCSV(reason),
              CleanCSV(why),
              CleanCSV(adjustment),
              CleanCSV(best_setup),
              DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
              DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
              DoubleToString(EffectiveRiskPercent(), 2),
              DoubleToString(g_last_risk_cash, 2),
              DoubleToString(g_last_volatility_risk_factor, 2),
              DoubleToString(g_last_loss_per_lot, 2),
              DoubleToString(stop_points, 1),
              DoubleToString(stop_risk_money, 2),
              DoubleToString(reward_points, 1),
              DoubleToString(planned_rr, 2),
              IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)),
              DoubleToString(entry_atr, _Digits),
              DoubleToString(average_entry_atr, _Digits),
              DoubleToString(EffectiveATRStopMultiplier(), 2),
              IntegerToString(StrategyAgreementCount(strategy)),
              IntegerToString(MathMax(1, InpMinAgreeingStrategies)),
              IntegerToString(g_sd_zone_count),
              DoubleToString(nearest_demand.low, _Digits),
              DoubleToString(nearest_demand.high, _Digits),
              CleanCSV(nearest_demand.label),
              DoubleToString(nearest_supply.low, _Digits),
              DoubleToString(nearest_supply.high, _Digits),
              CleanCSV(nearest_supply.label),
              DoubleToString(GetOpenProfitForMagic(), 2),
              DoubleToString(GetTodayClosedProfit(), 2),
              DoubleToString(GetTotalClosedProfit(), 2),
              CleanCSV(RegimeToText(CurrentMarketRegime())));
   FileClose(handle);
}

// V6.20: the journal file is shared by all charts, so on startup each
// chart must learn only from rows that belong to its own symbol, and the
// regime column feeds the per-regime learning buckets.
void LoadJournalMemory()
{
   if(!InpUseJournalLearning)
      return;

   int handle = FileOpen(InpJournalFileName, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(handle == INVALID_HANDLE)
      return;

   while(!FileIsEnding(handle))
   {
      FileReadString(handle);
      if(FileIsLineEnding(handle))
         break;
   }

   while(!FileIsEnding(handle))
   {
      string event_name = "";
      string row_symbol = "";
      string strategy = "";
      string result_text = "";
      string setup = "";
      string regime_text = "";
      double profit = 0.0;
      int column = 0;

      while(!FileIsEnding(handle))
      {
         string value = FileReadString(handle);
         if(column == 1) event_name = value;
         if(column == 3) row_symbol = value;
         if(column == 10) strategy = value;
         if(column == 11) result_text = value;
         if(column == 12) profit = StringToDouble(value);
         if(column == 16) setup = value;
         if(column == 43) regime_text = value;
         column++;
         if(FileIsLineEnding(handle))
            break;
      }

      if(event_name != "CLOSE")
         continue;
      if(row_symbol != _Symbol)
         continue;

      int regime = RegimeFromText(regime_text);
      for(int s = 0; s < STRATEGY_COUNT; s++)
      {
         if(StringFind(strategy, g_strategy_names[s]) >= 0)
         {
            g_strategy_trades[s]++;
            g_strategy_profit[s] += profit;
            if(result_text == "WIN")
               g_strategy_wins[s]++;
            else if(result_text == "LOSS")
               g_strategy_losses[s]++;

            if(regime > 0 && regime < REGIME_COUNT)
            {
               g_regime_trades[s][regime]++;
               g_regime_profit[s][regime] += profit;
               if(result_text == "WIN")
                  g_regime_wins[s][regime]++;
            }

            if(profit > g_strategy_best_setup_profit[s])
            {
               g_strategy_best_setup_profit[s] = profit;
               g_strategy_best_setup[s] = setup;
            }
         }
      }
   }

   FileClose(handle);
}

void UpdateStrategyMemory(string strategy, double profit, string setup)
{
   if(!InpUseJournalLearning)
      return;

   int regime = CurrentMarketRegime();
   for(int s = 0; s < STRATEGY_COUNT; s++)
   {
      if(StringFind(strategy, g_strategy_names[s]) >= 0)
      {
         g_strategy_trades[s]++;
         g_strategy_profit[s] += profit;
         if(profit > 0.0)
            g_strategy_wins[s]++;
         else if(profit < 0.0)
            g_strategy_losses[s]++;

         if(regime > 0 && regime < REGIME_COUNT)
         {
            g_regime_trades[s][regime]++;
            g_regime_profit[s][regime] += profit;
            if(profit > 0.0)
               g_regime_wins[s][regime]++;
         }

         if(profit > g_strategy_best_setup_profit[s])
         {
            g_strategy_best_setup_profit[s] = profit;
            g_strategy_best_setup[s] = setup;
         }
      }
   }
}

void ResetStrategyMemory()
{
   for(int i = 0; i < STRATEGY_COUNT; i++)
   {
      g_strategy_trades[i] = 0;
      g_strategy_wins[i] = 0;
      g_strategy_losses[i] = 0;
      g_strategy_profit[i] = 0.0;
      g_strategy_best_setup[i] = "";
      g_strategy_best_setup_profit[i] = -1.0e100;
      for(int r = 0; r < REGIME_COUNT; r++)
      {
         g_regime_trades[i][r] = 0;
         g_regime_wins[i][r] = 0;
         g_regime_profit[i][r] = 0.0;
      }
   }
}

double ApplyLearningToScore(double base_score, string strategy)
{
   if(!InpUseJournalLearning)
      return base_score;

   double factor = 1.0;
   int matched = 0;

   for(int s = 0; s < STRATEGY_COUNT; s++)
   {
      if(StringFind(strategy, g_strategy_names[s]) < 0)
         continue;

      matched++;
      if(g_strategy_trades[s] < InpLearningMinTrades)
         continue;

      double win_rate = 0.0;
      if(g_strategy_trades[s] > 0)
         win_rate = (double)g_strategy_wins[s] / (double)g_strategy_trades[s];

      if(win_rate >= 0.50 && g_strategy_profit[s] >= 0.0)
         factor += InpLearningMaxBoostPercent / 100.0 * (win_rate - 0.50) * 2.0;
      else
         factor -= InpLearningMaxPenaltyPercent / 100.0 * (0.50 - win_rate) * 2.0;
   }

   if(matched == 0)
      return base_score;

   factor = ClampDouble(factor, 1.0 - InpLearningMaxPenaltyPercent / 100.0, 1.0 + InpLearningMaxBoostPercent / 100.0);

   // V6.20 regime layer: a strategy is judged by how it performs in the
   // CURRENT market regime, not only by its blended overall record. A
   // strategy that keeps losing in this regime is benched entirely here.
   if(InpUseRegimeLearning)
   {
      int regime = CurrentMarketRegime();
      if(regime > 0 && regime < REGIME_COUNT)
      {
         for(int s = 0; s < STRATEGY_COUNT; s++)
         {
            if(StringFind(strategy, g_strategy_names[s]) < 0)
               continue;
            if(g_regime_trades[s][regime] < MathMax(2, InpRegimeLearningMinTrades))
               continue;

            double regime_wr = (double)g_regime_wins[s][regime] / (double)g_regime_trades[s][regime];

            if(InpBenchLosingStrategies && regime_wr * 100.0 < InpBenchWinRateThreshold &&
               g_regime_profit[s][regime] < 0.0)
               return 0.0;   // benched in this regime until conditions change

            double regime_factor = 1.0;
            if(regime_wr >= 0.50 && g_regime_profit[s][regime] >= 0.0)
               regime_factor += InpRegimeMaxBoostPercent / 100.0 * (regime_wr - 0.50) * 2.0;
            else
               regime_factor -= InpRegimeMaxPenaltyPercent / 100.0 * (0.50 - regime_wr) * 2.0;
            regime_factor = ClampDouble(regime_factor,
                                        1.0 - InpRegimeMaxPenaltyPercent / 100.0,
                                        1.0 + InpRegimeMaxBoostPercent / 100.0);
            factor *= regime_factor;
         }
      }
   }

   return ClampDouble(base_score * factor, 0.0, 100.0);
}

string MemorySummary()
{
   string text = "";
   for(int s = 0; s < STRATEGY_COUNT; s++)
   {
      string setup = g_strategy_best_setup[s];
      if(setup == "")
         setup = "collecting data";
      string part = g_strategy_names[s] + " best in " + setup;
      text = AppendToken(text, part);
   }
   return text;
}

EntryDealInfo FindEntryDeal(ulong position_id)
{
   EntryDealInfo info;
   info.found = false;
   info.strategy = "";
   info.direction = 0;
   info.volume = 0.0;
   info.open_price = 0.0;
   info.sl = 0.0;
   info.tp = 0.0;
   info.open_time = 0;

   if(position_id == 0 || !HistorySelect(0, TimeCurrent()))
      return info;

   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != position_id)
         continue;
      if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
         continue;

      info.found = true;
      info.strategy = ExpandStrategyFromComment(HistoryDealGetString(deal, DEAL_COMMENT));
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      info.direction = (type == DEAL_TYPE_BUY) ? 1 : -1;
      info.volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
      info.open_price = HistoryDealGetDouble(deal, DEAL_PRICE);
      info.sl = HistoryDealGetDouble(deal, DEAL_SL);
      info.tp = HistoryDealGetDouble(deal, DEAL_TP);
      info.open_time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      return info;
   }

   return info;
}

//+------------------------------------------------------------------+
//| Visuals (shortened for brevity – keep as in previous version)   |
//+------------------------------------------------------------------+
void RefreshVisuals()
{
   if(!InpDrawVisuals)
      return;

   if(InpClearOldVisuals)
      DeleteObjectsByPrefix("SCE312_");
   else
      DeleteObjectsByPrefix("SCE312_VIS_");

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, InpVisualLookbackBars + 40, rates);
   if(copied < 40)
   {
      if(InpShowDashboard)
         DrawDashboard();
      return;
   }

   if(InpShowPremiumDiscount)
      DrawCleanPremiumDiscount(rates, copied);
   if(InpShowSupportResistance)
      DrawCleanSupportResistance(rates, copied);
   if(InpShowSupportResistance && InpEnableRangeCycle)
      DrawRangeClusterLines(rates, copied);
   if(InpShowHistoricalTPTargets)
      DrawHistoricalTPTargets();
   if(InpShowMajorSwingLevels)
      DrawMajorSwingLevels();
   if(InpShowSupplyDemandZones)
      DrawCleanSupplyDemandZones();
   if(InpShowTrendLines)
      DrawCleanTrendLines();
   if(InpShowFairValueGaps || InpShowOrderBlocks)
      DrawCleanFVGAndOB(rates, copied);
   if(InpShowM30OrderBlocks)
      DrawM30OrderBlocks();
   if(InpShowCHOCH)
      DrawCleanCHOCH(rates, copied);
   if(InpShowDashboard)
      DrawDashboard();

   ChartRedraw(0);
}

void DrawDailyAndWeeklyLevels()
{
   double pdh = 0.0, pdl = 0.0;
   GetPreviousDailyLevels(pdh, pdl);
   if(pdh > 0.0)
      DrawHLine("SCE312_PDH", pdh, clrRed, "PDH");
   if(pdl > 0.0)
      DrawHLine("SCE312_PDL", pdl, clrRed, "PDL");

   MqlRates week[];
   ArraySetAsSeries(week, true);
   if(CopyRates(_Symbol, PERIOD_W1, 1, 1, week) == 1)
   {
      DrawHLine("SCE312_PWH", week[0].high, C'255,80,30', "PWH");
      DrawHLine("SCE312_PWL", week[0].low, C'255,80,30', "PWL");
   }
}

void DrawPremiumDiscount(const MqlRates &rates[], int copied)
{
   int lookback = MathMin(copied - 1, InpVisualLookbackBars);
   double high = rates[ArrayMaximumHigh(rates, lookback)].high;
   double low = rates[ArrayMinimumLow(rates, lookback)].low;
   if(high <= low)
      return;

   double mid = (high + low) * 0.5;
   double band = (high - low) * 0.035;
   datetime start = rates[lookback].time;
   datetime end = rates[0].time + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);

   DrawRectangle("SCE312_Equilibrium", start, mid + band, end, mid - band, C'225,228,232', "Equilibrium");
   DrawRectangle("SCE312_Discount", start, mid - band, end, low, C'210,255,210', "Discount");
   DrawRectangle("SCE312_Premium", start, high, end, mid + band, C'218,241,255', "Premium");
}

void DrawFVGAndOBVisuals(const MqlRates &rates[], int copied)
{
   int drawn_fvg = 0;
   int drawn_ob = 0;
   datetime end = rates[0].time + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);

   int max_i = MathMin(copied - 3, InpVisualLookbackBars);
   for(int i = 1; i <= max_i; i++)
   {
      double bull_gap = rates[i].low - rates[i + 2].high;
      if(bull_gap >= InpFVGMinGapPoints * _Point && drawn_fvg < 12)
      {
         string name = "SCE312_BullFVG_" + IntegerToString(i);
         DrawRectangle(name, rates[i + 2].time, rates[i].low, end, rates[i + 2].high, C'210,255,210', "Bullish FVG");
         drawn_fvg++;

         int ob = FindNearbyOBCandle(rates, copied, i, 1);
         if(ob > 0 && drawn_ob < 8)
         {
            DrawRectangle("SCE312_BullOB_" + IntegerToString(i), rates[ob].time, rates[ob].high,
                          end, rates[ob].low, C'185,255,185', "Bullish OB");
            drawn_ob++;
         }
      }

      double bear_gap = rates[i + 2].low - rates[i].high;
      if(bear_gap >= InpFVGMinGapPoints * _Point && drawn_fvg < 12)
      {
         string name = "SCE312_BearFVG_" + IntegerToString(i);
         DrawRectangle(name, rates[i + 2].time, rates[i + 2].low, end, rates[i].high, C'255,220,210', "Bearish FVG");
         drawn_fvg++;

         int ob = FindNearbyOBCandle(rates, copied, i, -1);
         if(ob > 0 && drawn_ob < 8)
         {
            DrawRectangle("SCE312_BearOB_" + IntegerToString(i), rates[ob].time, rates[ob].high,
                          end, rates[ob].low, C'255,180,150', "Bearish OB");
            drawn_ob++;
         }
      }
   }
}

void DrawStructureLabels(const MqlRates &rates[], int copied)
{
   int depth = MathMax(2, InpStructureSwingDepth);
   int last_high = -1, prev_high = -1;
   int last_low = -1, prev_low = -1;
   FindLastTwoSwingIndexes(rates, copied, depth, -1, last_high, prev_high);
   FindLastTwoSwingIndexes(rates, copied, depth, 1, last_low, prev_low);

   if(last_high > 0 && prev_high > 0)
   {
      bool bos = rates[1].close > rates[last_high].high;
      string label = bos ? "BOS" : "EQH";
      DrawText("SCE312_StructHigh_" + IntegerToString(last_high), rates[last_high].time, rates[last_high].high,
               label, bos ? clrLime : clrRed);
   }

   if(last_low > 0 && prev_low > 0)
   {
      bool bos = rates[1].close < rates[last_low].low;
      string label = bos ? "BOS" : "EQL";
      DrawText("SCE312_StructLow_" + IntegerToString(last_low), rates[last_low].time, rates[last_low].low,
               label, bos ? clrRed : C'45,150,90');
   }

   MarketStructure ms = AnalyzeStructure(rates, copied, depth);
   if(ms.bullish_choch)
      DrawText("SCE312_CHoCH_Bull", rates[1].time, rates[1].low, "CHoCH", C'60,180,120');
   if(ms.bearish_choch)
      DrawText("SCE312_CHoCH_Bear", rates[1].time, rates[1].high, "CHoCH", clrRed);
}

void DrawRectangle(string name, datetime t1, double p1, datetime t2, double p2, color clr, string label)
{
   double high = MathMax(p1, p2);
   double low = MathMin(p1, p2);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, high, t2, low);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   DrawText(name + "_Label", t2, (high + low) * 0.5, label, clrBlack);
}

void DrawHLine(string name, double price, color clr, string label)
{
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   datetime t = iTime(_Symbol, InpStructureTF, 0) + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);
   DrawText(name + "_Label", t, price, label, clr);
}

void DrawText(string name, datetime t, double price, string text, color clr)
{
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DeleteObjectsByPrefix(string prefix)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void ApplyCleanChartTheme()
{
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'248,249,250');
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'30,35,40');
   ChartSetInteger(0, CHART_COLOR_GRID, C'230,230,230');
}

void DrawCleanPremiumDiscount(const MqlRates &rates[], int copied)
{
   DealingRange range;
   if(!GetConfirmedDealingRange(range))
      return;

   int lookback = MathMin(copied - 1, MathMin(InpVisualLookbackBars, 140));
   datetime start = rates[lookback].time;
   datetime end = rates[0].time + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);

   DrawCleanZoneRectangle("SCE312_VIS_Premium", start, range.high, end,
                          range.equilibrium + range.equilibrium_band, C'218,241,255', "Premium", true);
   DrawCleanZoneRectangle("SCE312_VIS_Equilibrium", start,
                          range.equilibrium + range.equilibrium_band, end,
                          range.equilibrium - range.equilibrium_band, C'226,226,226', "Equilibrium", true);
   DrawCleanZoneRectangle("SCE312_VIS_Discount", start,
                          range.equilibrium - range.equilibrium_band, end,
                          range.low, C'230,252,233', "Discount", true);
}

void DrawCleanSupportResistance(const MqlRates &rates[], int copied)
{
   double tolerance = GetSRZoneTolerance();
   PriceZone support = FindSRZone(rates, copied, 1, tolerance);
   PriceZone resistance = FindSRZone(rates, copied, -1, tolerance);

   int start_index = MathMin(copied - 1, MathMin(InpSRLookbackBars, 130));
   datetime start = rates[start_index].time;
   datetime end = rates[0].time + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);

   if(support.valid)
   {
      double level = (support.low + support.high) * 0.5;
      DrawCleanZoneRectangle("SCE312_VIS_SR_SupportZone", start, support.high, end, support.low, C'220,250,226', "Support", true);
      DrawCleanPriceLine("SCE312_VIS_SR_SupportLine", level, C'0,155,85', STYLE_SOLID, 2, "SRBounce Support");
      DrawCleanText("SCE312_VIS_SR_SupportLabel", end, level, "Support (" + IntegerToString(support.touches) + " touches)", C'0,120,65', 9);
   }

   if(resistance.valid)
   {
      double level = (resistance.low + resistance.high) * 0.5;
      DrawCleanZoneRectangle("SCE312_VIS_SR_ResistanceZone", start, resistance.high, end, resistance.low, C'255,232,226', "Resistance", true);
      DrawCleanPriceLine("SCE312_VIS_SR_ResistanceLine", level, C'205,50,45', STYLE_SOLID, 2, "SRBounce Resistance");
      DrawCleanText("SCE312_VIS_SR_ResistanceLabel", end, level, "Resistance (" + IntegerToString(resistance.touches) + " touches)", C'180,45,40', 9);
   }

   PriceZone rr_support = FindBrokenRetestedZone(rates, copied, 1, tolerance);
   if(rr_support.valid)
   {
      double level = (rr_support.low + rr_support.high) * 0.5;
      DrawCleanPriceLine("SCE312_VIS_SR_RoleSupport", level, C'0,150,90', STYLE_DASH, 2, "Resistance broken and retested as new support");
      DrawCleanText("SCE312_VIS_SR_RoleSupportLabel", end, level, "Resistance -> Support retest", C'0,130,80', 9);
   }

   PriceZone rr_resistance = FindBrokenRetestedZone(rates, copied, -1, tolerance);
   if(rr_resistance.valid)
   {
      double level = (rr_resistance.low + rr_resistance.high) * 0.5;
      DrawCleanPriceLine("SCE312_VIS_SR_RoleResistance", level, C'220,55,45', STYLE_DASH, 2, "Support broken and retested as new resistance");
      DrawCleanText("SCE312_VIS_SR_RoleResistanceLabel", end, level, "Support -> Resistance retest", C'205,45,40', 9);
   }
}

void DrawHistoricalTPTargets()
{
   int active_direction = ActivePositionDirection();
   if(active_direction == 0)
      return;

   ulong active_ticket = 0;
   double active_entry = 0.0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         active_ticket = ticket;
         active_entry = PositionGetDouble(POSITION_PRICE_OPEN);
         break;
      }
   }

   // For a live trade, display the exact targets being managed rather than a
   // generic nearest-fractal list.  This keeps TP High/Low 1 and 3 aligned with
   // the actual staged order-management logic.
   if(InpUseStagedHistoricalTargets && active_ticket != 0 && HasStagedTargetState(active_ticket))
   {
      double staged_levels[3];
      staged_levels[0] = GlobalVariableGet(PositionTP1Key(active_ticket));
      staged_levels[1] = GlobalVariableGet(PositionTP3Key(active_ticket));
      staged_levels[2] = GlobalVariableGet(PositionRunnerTPKey(active_ticket));
      string staged_labels[3] = {"1", "3", "2R Runner"};
      int limit = MathMin(3, MathMax(0, InpMaxVisibleHistoricalTPTargets));
      datetime staged_label_time = iTime(_Symbol, PERIOD_M15, 0) +
                                    (datetime)(PeriodSeconds(PERIOD_M15) * InpVisualExtendBars);
      color staged_color = (active_direction == 1) ? C'75,115,205' : C'150,95,190';
      for(int slot = 0; slot < limit; slot++)
      {
         if(!IsTargetBeyondEntry(active_direction, active_entry, staged_levels[slot]))
            continue;
         string prefix = (active_direction == 1) ? "TPHigh" : "TPLow";
         string name = "SCE312_VIS_Historical_" + prefix + "_Stage" + IntegerToString(slot + 1);
         string label = (active_direction == 1 ? "TP High " : "TP Low ") + staged_labels[slot];
         DrawCleanPriceLine(name, staged_levels[slot], staged_color, STYLE_DOT, 1,
                             "Active staged historical take-profit");
         DrawCleanText(name + "_Label", staged_label_time, staged_levels[slot], label, staged_color, 8);
      }
      return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int lookback = MathMax(1000, InpM15HistoricalLookback);
   int copied = CopyRates(_Symbol, PERIOD_M15, 0, lookback + 10, rates);
   int depth = MathMax(2, InpFractalDepth);
   if(copied < depth * 2 + 20)
      return;

   int target_limit = MathMin(6, MathMax(0, InpMaxVisibleHistoricalTPTargets));
   if(target_limit == 0)
      return;

   double current_price = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) +
                           SymbolInfoDouble(_Symbol, SYMBOL_BID)) * 0.5;
   double atr = GetATR(_Symbol, PERIOD_M15, InpTrendATRPeriod, 1);
   double duplicate_tolerance = MathMax(10.0 * _Point, atr * 0.25);
   datetime label_time = iTime(_Symbol, PERIOD_M15, 0) +
                         (datetime)(PeriodSeconds(PERIOD_M15) * InpVisualExtendBars);
   double chosen_highs[6];
   double chosen_lows[6];
   ArrayInitialize(chosen_highs, 0.0);
   ArrayInitialize(chosen_lows, 0.0);

   int direction = active_direction;
   for(int slot = 0; slot < target_limit; slot++)
   {
      double best_price = 0.0;
      double best_distance = DBL_MAX;
      for(int i = depth + 1; i < copied - depth; i++)
      {
         bool swing = (direction == 1) ? IsSwingHigh(rates, copied, i, depth)
                                       : IsSwingLow(rates, copied, i, depth);
         if(!swing)
            continue;

         double candidate = (direction == 1) ? rates[i].high : rates[i].low;
         double distance = (direction == 1) ? candidate - current_price : current_price - candidate;
         if(distance <= 2.0 * _Point || distance >= best_distance)
            continue;

         bool duplicate = false;
         for(int j = 0; j < slot; j++)
         {
            double selected_price = (direction == 1) ? chosen_highs[j] : chosen_lows[j];
            if(MathAbs(candidate - selected_price) <= duplicate_tolerance)
            {
               duplicate = true;
               break;
            }
         }
         if(!duplicate)
         {
            best_price = candidate;
            best_distance = distance;
         }
      }

      if(best_price <= 0.0)
         break;
      if(direction == 1)
         chosen_highs[slot] = best_price;
      else
         chosen_lows[slot] = best_price;

      string prefix = (direction == 1) ? "TPHigh" : "TPLow";
      color line_color = (direction == 1) ? C'75,115,205' : C'150,95,190';
      string name = "SCE312_VIS_Historical_" + prefix + "_" + IntegerToString(slot + 1);
      DrawCleanPriceLine(name, best_price, line_color, STYLE_DOT, 1,
                          "Historical M15 fractal potential take-profit");
      DrawCleanText(name + "_Label", label_time, best_price,
                    (direction == 1 ? "TP High " : "TP Low ") + IntegerToString(slot + 1),
                    line_color, 8);
   }
}

int MajorSwingDepthForTimeframe(ENUM_TIMEFRAMES timeframe)
{
   int depth = MathMax(3, InpMajorSwingDepth);
   // H4 must be materially stricter than M30; otherwise an ordinary H4 pullback
   // is incorrectly shown as a "major" low/high.
   if(timeframe == PERIOD_H4)
      return depth + 2;
   if(timeframe == PERIOD_H1)
      return depth + 1;
   return depth;
}

bool IsConfirmedMajorSwing(const MqlRates &rates[], int copied, int index,
                           int direction, int depth, int break_window,
                           double atr, double &strength)
{
   strength = 0.0;
   bool pivot = (direction == 1) ? IsSwingHigh(rates, copied, index, depth)
                                 : IsSwingLow(rates, copied, index, depth);
   if(!pivot)
      return false;

   // With a series array, larger indexes are older candles.  A real major low
   // must subsequently break the high that existed before it; a major high is
   // the exact reverse.  This prevents a small nearby pullback from winning
   // merely because it is closest to the current price.
   int older_end = MathMin(copied - depth - 1, index + break_window);
   int newer_start = MathMax(depth + 1, index - break_window);
   if(older_end <= index || newer_start >= index)
      return false;

   // A high becomes major only after price breaks the low preceding that high.
   // A low becomes major only after price breaks the high preceding that low.
   double prior_structure = (direction == 1) ? DBL_MAX : -DBL_MAX;
   double post_structure = (direction == 1) ? DBL_MAX : -DBL_MAX;
   for(int k = index + 1; k <= older_end; k++)
   {
      if(direction == 1)
         prior_structure = MathMin(prior_structure, rates[k].low);
      else
         prior_structure = MathMax(prior_structure, rates[k].high);
   }
   for(int k = newer_start; k < index; k++)
   {
      if(direction == 1)
         post_structure = MathMin(post_structure, rates[k].low);
      else
         post_structure = MathMax(post_structure, rates[k].high);
   }

   double pivot_price = (direction == 1) ? rates[index].high : rates[index].low;
   double safe_atr = MathMax(10.0 * _Point, atr);
   double break_buffer = MathMax(3.0 * _Point, safe_atr * 0.25);
   bool broke_structure = (direction == 1) ? post_structure < prior_structure - break_buffer
                                           : post_structure > prior_structure + break_buffer;
   double impulse = (direction == 1) ? pivot_price - post_structure
                                     : post_structure - pivot_price;
   if(!broke_structure || impulse < safe_atr * MathMax(1.0, InpMajorSwingMinImpulseATR))
      return false;

   strength = impulse / safe_atr;
   return true;
}

bool FindDominantMajorSwingLevel(ENUM_TIMEFRAMES timeframe, int direction,
                                 double current_price, double &level,
                                 datetime &swing_time)
{
   level = 0.0;
   swing_time = 0;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int requested = (timeframe == PERIOD_M30) ? 700 : (timeframe == PERIOD_H1 ? 420 : 360);
   int copied = CopyRates(_Symbol, timeframe, 0, requested, rates);
   int depth = MajorSwingDepthForTimeframe(timeframe);
   int break_window = MathMax(depth * 3, InpMajorSwingBreakWindow);
   if(copied < depth * 2 + break_window + 20)
      return false;

   double atr = GetATR(_Symbol, timeframe, InpTrendATRPeriod, 1);
   double best_strength = -1.0;
   int best_index = -1;
   for(int i = depth + 1; i < copied - depth; i++)
   {
      double strength = 0.0;
      if(!IsConfirmedMajorSwing(rates, copied, i, direction, depth, break_window, atr, strength))
         continue;

      double candidate = (direction == 1) ? rates[i].high : rates[i].low;
      bool is_target_side = (direction == 1) ? candidate > current_price + 2.0 * _Point
                                              : candidate < current_price - 2.0 * _Point;
      if(!is_target_side)
         continue;

      // Choose the dominant structural pivot, not the closest minor one.  On a
      // tie, favour the more recent confirmed major swing.
      if(strength > best_strength + 0.05 ||
         (MathAbs(strength - best_strength) <= 0.05 && (best_index < 0 || i < best_index)))
      {
         best_strength = strength;
         best_index = i;
         level = candidate;
         swing_time = rates[i].time;
      }
   }
   return level > 0.0;
}

void DrawMajorSwingLevels()
{
   if(InpMaxMajorSwingLevelsPerTF <= 0)
      return;

   ENUM_TIMEFRAMES timeframes[3] = {PERIOD_M30, PERIOD_H1, PERIOD_H4};
   string names[3] = {"M30", "H1", "H4"};
   double current_price = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) +
                           SymbolInfoDouble(_Symbol, SYMBOL_BID)) * 0.5;
   datetime label_time = iTime(_Symbol, InpStructureTF, 0) +
                         (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);

   for(int t = 0; t < 3; t++)
   {
      double high = 0.0;
      datetime high_time = 0;
      if(FindDominantMajorSwingLevel(timeframes[t], 1, current_price, high, high_time))
      {
         string high_name = "SCE312_VIS_Major_" + names[t] + "_High";
         DrawCleanPriceLine(high_name, high, C'70,105,185', STYLE_DASHDOT, 1,
                             names[t] + " major prior high / buy target");
         DrawCleanText(high_name + "_Label", label_time, high,
                       names[t] + " Major High (" + TimeToString(high_time, TIME_DATE|TIME_MINUTES) + ")",
                       C'70,105,185', 8);
      }

      double low = 0.0;
      datetime low_time = 0;
      if(FindDominantMajorSwingLevel(timeframes[t], -1, current_price, low, low_time))
      {
         string low_name = "SCE312_VIS_Major_" + names[t] + "_Low";
         DrawCleanPriceLine(low_name, low, C'145,85,180', STYLE_DASHDOT, 1,
                             names[t] + " major prior low / sell target");
         DrawCleanText(low_name + "_Label", label_time, low,
                       names[t] + " Major Low (" + TimeToString(low_time, TIME_DATE|TIME_MINUTES) + ")",
                       C'145,85,180', 8);
      }
   }
}

int ActivePositionDirection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      return ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   }
   return 0;
}

void SyncHistoricalTPVisuals()
{
   int direction = ActivePositionDirection();
   if(direction == g_last_tp_visual_direction)
      return;

   DeleteObjectsByPrefix("SCE312_VIS_Historical_");
   g_last_tp_visual_direction = direction;
   if(direction != 0 && InpShowHistoricalTPTargets)
   {
      DrawHistoricalTPTargets();
      ChartRedraw(0);
   }
}

void DrawCleanSupplyDemandZones()
{
   if(!InpEnableSupplyDemandZones || g_sd_zone_count <= 0)
      return;

   datetime end = iTime(_Symbol, InpStructureTF, 0) + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);
   int drawn = 0;
   for(int i = 0; i < g_sd_zone_count && drawn < MathMax(0, InpMaxVisibleSDZones); i++)
   {
      PriceZone zone = g_sd_zones[i];
      if(!zone.valid)
         continue;

      color fill = (zone.direction == 1) ? C'214,250,222' : C'255,225,220';
      color text = (zone.direction == 1) ? C'0,125,75' : C'190,55,45';
      string name = "SCE312_VIS_SD_" + IntegerToString(i);
      DrawCleanZoneRectangle(name, zone.start_time, zone.high, end, zone.low, fill, zone.label, true);
      DrawCleanText(name + "_Strength", end, (zone.high + zone.low) * 0.5,
                    zone.label + " | touches " + IntegerToString(zone.touches), text, 8);
      drawn++;
   }
}

void DrawCleanTrendLines()
{
   TrendLine descending_h1, descending_h4, ascending_h1, ascending_h4;
   if(BuildThreePointTrendLine(InpTrendHigherTF2, -1, descending_h1))
      DrawCleanTrendLine("SCE312_VIS_TL_H1_Resistance", descending_h1, C'190,70,70',
                         TimeframeToText(InpTrendHigherTF2) + " Trendline Resistance");
   if(BuildThreePointTrendLine(InpTrendHigherTF1, -1, descending_h4))
      DrawCleanTrendLine("SCE312_VIS_TL_H4_Resistance", descending_h4, C'150,35,35',
                         TimeframeToText(InpTrendHigherTF1) + " Trendline Resistance");
   if(BuildThreePointTrendLine(InpTrendHigherTF2, 1, ascending_h1))
      DrawCleanTrendLine("SCE312_VIS_TL_H1_Support", ascending_h1, C'40,150,85',
                         TimeframeToText(InpTrendHigherTF2) + " Trendline Support");
   if(BuildThreePointTrendLine(InpTrendHigherTF1, 1, ascending_h4))
      DrawCleanTrendLine("SCE312_VIS_TL_H4_Support", ascending_h4, C'20,110,70',
                         TimeframeToText(InpTrendHigherTF1) + " Trendline Support");
}

void DrawCleanFVGAndOB(const MqlRates &rates[], int copied)
{
   int drawn_fvg = 0;
   int drawn_ob = 0;
   int fvg_limit = MathMax(0, InpMaxVisibleFVG);
   int ob_limit = MathMax(0, InpMaxVisibleOB);
   datetime end = rates[0].time + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);
   int max_i = MathMin(copied - 3, MathMin(InpVisualLookbackBars, 180));

   for(int i = 1; i <= max_i; i++)
   {
      if(InpShowFairValueGaps && drawn_fvg < fvg_limit)
      {
         double bull_low = rates[i + 2].high;
         double bull_high = rates[i].low;
         if(bull_high - bull_low >= InpFVGMinGapPoints * _Point && !ZoneTouchedAfterIndex(rates, i, bull_low, bull_high))
         {
            DrawCleanZoneRectangle("SCE312_VIS_BullFVG_" + IntegerToString(i), rates[i + 2].time, bull_high,
                                   end, bull_low, C'218,246,255', "Bullish FVG", true);
            drawn_fvg++;
         }

         double bear_low = rates[i].high;
         double bear_high = rates[i + 2].low;
         if(bear_high - bear_low >= InpFVGMinGapPoints * _Point && !ZoneTouchedAfterIndex(rates, i, bear_low, bear_high))
         {
            DrawCleanZoneRectangle("SCE312_VIS_BearFVG_" + IntegerToString(i), rates[i + 2].time, bear_high,
                                   end, bear_low, C'255,229,216', "Bearish FVG", true);
            drawn_fvg++;
         }
      }

      if(InpShowOrderBlocks && drawn_ob < ob_limit)
      {
         int bull_ob = FindNearbyOBCandle(rates, copied, i, 1);
         if(bull_ob > 0 && !IsMitigated(rates, bull_ob, 1))
         {
            DrawCleanZoneRectangle("SCE312_VIS_BullOB_" + IntegerToString(bull_ob), rates[bull_ob].time, rates[bull_ob].high,
                                   end, rates[bull_ob].low, C'190,238,198', "Bullish OB", true);
            drawn_ob++;
         }
      }

      if(InpShowOrderBlocks && drawn_ob < ob_limit)
      {
         int bear_ob = FindNearbyOBCandle(rates, copied, i, -1);
         if(bear_ob > 0 && !IsMitigated(rates, bear_ob, -1))
         {
            DrawCleanZoneRectangle("SCE312_VIS_BearOB_" + IntegerToString(bear_ob), rates[bear_ob].time, rates[bear_ob].high,
                                   end, rates[bear_ob].low, C'246,184,164', "Bearish OB", true);
            drawn_ob++;
         }
      }

      if(drawn_fvg >= fvg_limit && drawn_ob >= ob_limit)
         break;
   }
}

void DrawCleanCHOCH(const MqlRates &rates[], int copied)
{
   int depth = MathMax(2, InpStructureSwingDepth);
   MarketStructure ms = AnalyzeStructure(rates, copied, depth);
   int last_high = -1, prev_high = -1;
   int last_low = -1, prev_low = -1;
   FindLastTwoSwingIndexes(rates, copied, depth, -1, last_high, prev_high);
   FindLastTwoSwingIndexes(rates, copied, depth, 1, last_low, prev_low);
   datetime label_time = rates[1].time +
                         (datetime)(PeriodSeconds(InpStructureTF) *
                                    MathMax(1, InpStructureLabelOffsetBars));

   if((ms.bullish_bos || ms.bullish_choch) && prev_high > 0)
   {
      string label = ms.bullish_choch ? "Bullish CHoCH" : "Bullish BOS";
      DrawCleanStructureLine("SCE312_VIS_Structure_Bull", rates[prev_high].time, rates[prev_high].high,
                             label_time, rates[prev_high].high, C'0,150,90', label);
   }
   if((ms.bearish_bos || ms.bearish_choch) && prev_low > 0)
   {
      string label = ms.bearish_choch ? "Bearish CHoCH" : "Bearish BOS";
      DrawCleanStructureLine("SCE312_VIS_Structure_Bear", rates[prev_low].time, rates[prev_low].low,
                             label_time, rates[prev_low].low, C'220,55,45', label);
   }
}

void DrawCleanZoneRectangle(string name, datetime t1, double p1, datetime t2, double p2, color clr, string label, bool background)
{
   double high = MathMax(p1, p2);
   double low = MathMin(p1, p2);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, high, t2, low);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, background);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   DrawCleanText(name + "_Label", t2, (high + low) * 0.5, label, C'25,30,35', 9);
}

void DrawCleanPriceLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string tooltip)
{
   if(price <= 0.0)
      return;
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

void DrawCleanTrendLine(string name, const TrendLine &line, color clr, string label)
{
   if(!line.valid)
      return;

   datetime end_time = iTime(_Symbol, InpStructureTF, 0) + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);
   double end_price = ProjectTrendLine(line, end_time);

   ObjectCreate(0, name, OBJ_TREND, 0, line.t1, line.p1, end_time, end_price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   DrawCleanText(name + "_Label", end_time, end_price, label, clr, 9);
}

void DrawCleanStructureLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, string label)
{
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   DrawCleanText(name + "_Label", t2, p2, label, clr, 10);
}

void DrawCleanText(string name, datetime t, double price, string text, color clr, int font_size)
{
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void RefreshDashboardIfNeeded(bool force)
{
   if(!InpShowDashboard)
      return;

   datetime now = TimeCurrent();
   int interval = MathMax(1, InpDashboardRefreshSeconds);
   if(!force && g_last_dashboard_refresh_time > 0 && now - g_last_dashboard_refresh_time < interval)
      return;

   DrawDashboard();
   g_last_dashboard_refresh_time = now;
}

void DrawDashboard()
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   DrawDashboardPanel("SCE312_DASH_Main", CORNER_LEFT_UPPER, x, y, 360, 252, C'20,24,31', C'70,86,100');
   DrawDashboardLabel("SCE312_DASH_Title", CORNER_LEFT_UPPER, x + 12, y + 10,
                      "NDLOVUENGINE V6.37", C'255,255,255', 11, ANCHOR_LEFT_UPPER);
   DrawDashboardLabel("SCE312_DASH_Subtitle", CORNER_LEFT_UPPER, x + 12, y + 30,
                      "Fractal SR | Trendline | FVG retest", C'155,205,255', 8, ANCHOR_LEFT_UPPER);
   DrawDashboardLabel("SCE312_DASH_Symbol", CORNER_LEFT_UPPER, x + 12, y + 54,
                      "Symbol: " + _Symbol, C'200,220,240', 9, ANCHOR_LEFT_UPPER);

   string h1_regime = DashboardStructureText(InpTrendHigherTF1);
   string m15_structure = DashboardM15StateText();
   color regime_color = (h1_regime == "Bullish") ? C'120,235,170' :
                        (h1_regime == "Bearish") ? C'255,140,120' : C'210,210,160';
   color structure_color = (m15_structure == "Bullish") ? C'120,235,170' :
                           (m15_structure == "Bearish") ? C'255,140,120' : C'210,210,160';
   DrawDashboardLabel("SCE312_DASH_Regime", CORNER_LEFT_UPPER, x + 12, y + 74,
                      "H1: " + h1_regime + " | Market: " + RegimeToText(CurrentMarketRegime()),
                      regime_color, 9, ANCHOR_LEFT_UPPER);
   DrawDashboardLabel("SCE312_DASH_Bias", CORNER_LEFT_UPPER, x + 12, y + 94,
                      "M15 structure: " + m15_structure, structure_color, 9, ANCHOR_LEFT_UPPER);
   DrawDashboardLabel("SCE312_DASH_Signal", CORNER_LEFT_UPPER, x + 12, y + 114,
                      "Signal: " + g_last_dashboard_signal, C'180,210,255', 9, ANCHOR_LEFT_UPPER);

   // V6.10: show the pilot sizing state so it is always clear whether the
   // next entry will be a minimum-lot pilot or a fully sized trade.
   string pilot_text = "OFF";
   color pilot_color = C'170,175,180';
   if(InpUsePilotFirstTrade)
   {
      int stage = PilotStage();
      if(stage == 0) { pilot_text = "Next trade: minimum-lot pilot"; pilot_color = C'255,215,130'; }
      else if(stage == 1) { pilot_text = "Pilot running - awaiting confirmation"; pilot_color = C'160,205,255'; }
      else { pilot_text = "Trend confirmed - full sizing"; pilot_color = C'120,235,170'; }
   }
   DrawDashboardLabel("SCE312_DASH_Pilot", CORNER_LEFT_UPPER, x + 12, y + 134,
                      "Pilot: " + pilot_text, pilot_color, 8, ANCHOR_LEFT_UPPER);

   string lock_text = g_daily_locked ? ("LOCKED - " + g_daily_lock_reason) : "OPEN";
   color lock_color = g_daily_locked ? C'255,118,100' : C'120,235,170';
   DrawDashboardLabel("SCE312_DASH_State", CORNER_LEFT_UPPER, x + 12, y + 154,
                      "Trading: " + lock_text, lock_color, 8, ANCHOR_LEFT_UPPER);

   double closed_daily = GetTodayClosedProfit();
   double open_pl = GetOpenProfitForMagic();
   double daily_pl = closed_daily;
   if(InpDailyLimitsUseFloatingPL)
      daily_pl += open_pl;
   DrawDashboardLabel("SCE312_DASH_PL", CORNER_LEFT_UPPER, x + 12, y + 174,
                      "Today P/L: " + DoubleToString(daily_pl, 2) + " | Open: " + DoubleToString(open_pl, 2),
                      daily_pl >= 0.0 ? C'120,235,170' : C'255,118,100', 8, ANCHOR_LEFT_UPPER);
   double drawdown = DashboardDrawdownPercent();
   DrawDashboardLabel("SCE312_DASH_DD", CORNER_LEFT_UPPER, x + 12, y + 194,
                      "Drawdown: " + DoubleToString(drawdown, 2) + "%",
                      drawdown < InpMaxDrawdownPercent * 0.6 ? C'170,200,170' : C'255,170,140', 8, ANCHOR_LEFT_UPPER);
   DrawDashboardLabel("SCE312_DASH_Last", CORNER_LEFT_UPPER, x + 12, y + 214,
                      "Last trade: " + DashboardLastTradeText(), C'200,210,220', 8, ANCHOR_LEFT_UPPER);
   string no_trade = (g_last_risk_reject_reason == "") ? g_last_dashboard_signal : g_last_risk_reject_reason;
   DrawDashboardLabel("SCE312_DASH_NoTrade", CORNER_LEFT_UPPER, x + 12, y + 234,
                      "No-trade: " + no_trade, C'180,185,195', 8, ANCHOR_LEFT_UPPER);
}

string DashboardStructureText(ENUM_TIMEFRAMES timeframe)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, timeframe, 0, 30, rates) < 30)
      return "Scanning";

   int structure_trend = GetResponsiveStructureTrend(timeframe);
   if(structure_trend > 0)
      return "Bullish";
   if(structure_trend < 0)
      return "Bearish";
   return "Ranging";
}

string DashboardM15StateText()
{
   DealingRange range;
   if(GetConfirmedDealingRange(range) && GetDealingRangeTrend() == 0)
   {
      MqlRates structure[];
      ArraySetAsSeries(structure, true);
      int copied = CopyRates(_Symbol, InpStructureTF, 0,
                             MathMax(80, InpRangeReversalLookbackBars + 30), structure);
      if(copied >= 30)
      {
         int shift_index = -1;
         double level = 0.0;
         if(FindRecentStructureShiftLevel(1, structure, copied, shift_index, level) &&
            HasRangeReversalOrigin(1, range, structure, copied, shift_index))
            return "Bullish reversal";
         if(FindRecentStructureShiftLevel(-1, structure, copied, shift_index, level) &&
            HasRangeReversalOrigin(-1, range, structure, copied, shift_index))
            return "Bearish reversal";
      }
   }
   return DashboardStructureText(InpStructureTF);
}

double DashboardDrawdownPercent()
{
   static double peak_equity = 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   peak_equity = MathMax(peak_equity, equity);
   return peak_equity > 0.0 ? (peak_equity - equity) * 100.0 / peak_equity : 0.0;
}

string DashboardLastTradeText()
{
   datetime from = TimeCurrent() - 180 * 86400;
   if(!HistorySelect(from, TimeCurrent()))
      return "No history";

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || (long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;

      double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                      HistoryDealGetDouble(deal, DEAL_SWAP) +
                      HistoryDealGetDouble(deal, DEAL_COMMISSION);
      return (profit >= 0.0 ? "Win " : "Loss ") + DoubleToString(profit, 2);
   }
   return "No closed trade";
}

void DrawDashboardPanel(string name, ENUM_BASE_CORNER corner, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawDashboardLabel(string name, ENUM_BASE_CORNER corner, int x, int y, string text, color clr, int font_size, int anchor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

string StrategyStatusText(int index, bool enabled)
{
   if(!enabled)
      return "OFF";

   int trades = g_strategy_trades[index];
   int wins = g_strategy_wins[index];
   string wr = "new data";
   if(trades > 0)
      wr = DoubleToString((double)wins * 100.0 / (double)trades, 0) + "% WR";
   return "ON | " + IntegerToString(trades) + " trades | " + wr;
}

color StrategyColor(bool enabled)
{
   return enabled ? C'120,235,170' : C'170,175,180';
}

bool ZoneTouchedAfterIndex(const MqlRates &rates[], int older_index, double low, double high)
{
   for(int j = 1; j < older_index; j++)
   {
      if(rates[j].low <= high && rates[j].high >= low)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Market structure helpers (keep as in previous version)           |
//+------------------------------------------------------------------+
MarketStructure AnalyzeStructure(const MqlRates &rates[], int copied, int depth)
{
   MarketStructure ms;
   ms.trend = 0;
   ms.last_high = 0.0;
   ms.prev_high = 0.0;
   ms.last_low = 0.0;
   ms.prev_low = 0.0;
   ms.idm = 0.0;
   ms.dealing_high = 0.0;
   ms.dealing_low = 0.0;
   ms.bullish_bos = false;
   ms.bearish_bos = false;
   ms.bullish_choch = false;
   ms.bearish_choch = false;

   int last_high_idx = -1, prev_high_idx = -1;
   int last_low_idx = -1, prev_low_idx = -1;
   FindLastTwoSwingIndexes(rates, copied, depth, -1, last_high_idx, prev_high_idx);
   FindLastTwoSwingIndexes(rates, copied, depth, 1, last_low_idx, prev_low_idx);

   if(last_high_idx > 0) ms.last_high = rates[last_high_idx].high;
   if(prev_high_idx > 0) ms.prev_high = rates[prev_high_idx].high;
   if(last_low_idx > 0) ms.last_low = rates[last_low_idx].low;
   if(prev_low_idx > 0) ms.prev_low = rates[prev_low_idx].low;

   if(ms.last_high > ms.prev_high && ms.last_low > ms.prev_low && ms.prev_high > 0.0 && ms.prev_low > 0.0)
      ms.trend = 1;
   else if(ms.last_high < ms.prev_high && ms.last_low < ms.prev_low && ms.prev_high > 0.0 && ms.prev_low > 0.0)
      ms.trend = -1;

   ms.dealing_high = HighestHighFromRates(rates, copied, 80);
   ms.dealing_low = LowestLowFromRates(rates, copied, 80);

   if(ms.trend >= 0 && ms.last_low > 0.0)
      ms.idm = ms.last_low;
   if(ms.trend < 0 && ms.last_high > 0.0)
      ms.idm = ms.last_high;

   if(ms.prev_high > 0.0 && rates[1].close > ms.prev_high)
   {
      ms.bullish_bos = (ms.trend >= 0);
      ms.bullish_choch = (ms.trend < 0);
   }
   if(ms.prev_low > 0.0 && rates[1].close < ms.prev_low)
   {
      ms.bearish_bos = (ms.trend <= 0);
      ms.bearish_choch = (ms.trend > 0);
   }

   return ms;
}

bool IsSwingHigh(const MqlRates &rates[], int copied, int index, int depth)
{
   if(index < depth || index + depth >= copied)
      return false;
   for(int i = 1; i <= depth; i++)
   {
      if(rates[index].high <= rates[index - i].high)
         return false;
      if(rates[index].high <= rates[index + i].high)
         return false;
   }
   return true;
}

bool IsSwingLow(const MqlRates &rates[], int copied, int index, int depth)
{
   if(index < depth || index + depth >= copied)
      return false;
   for(int i = 1; i <= depth; i++)
   {
      if(rates[index].low >= rates[index - i].low)
         return false;
      if(rates[index].low >= rates[index + i].low)
         return false;
   }
   return true;
}

void FindLastTwoSwingIndexes(const MqlRates &rates[],
                             int copied,
                             int depth,
                             int direction,
                             int &last_idx,
                             int &prev_idx)
{
   last_idx = -1;
   prev_idx = -1;
   for(int i = depth + 1; i < copied - depth; i++)
   {
      bool swing = (direction == 1) ? IsSwingLow(rates, copied, i, depth) : IsSwingHigh(rates, copied, i, depth);
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

double FindRecentSwingHigh(const MqlRates &rates[], int copied, int depth, int start)
{
   for(int i = MathMax(start, depth + 1); i < copied - depth; i++)
      if(IsSwingHigh(rates, copied, i, depth))
         return rates[i].high;
   return 0.0;
}

double FindRecentSwingLow(const MqlRates &rates[], int copied, int depth, int start)
{
   for(int i = MathMax(start, depth + 1); i < copied - depth; i++)
      if(IsSwingLow(rates, copied, i, depth))
         return rates[i].low;
   return 0.0;
}

PriceZone FindLatestFVG(const MqlRates &rates[], int copied, int direction, int min_points)
{
   PriceZone zone = PriceZoneEmpty();
   double min_gap = min_points * _Point;
   for(int i = 1; i < copied - 3; i++)
   {
      if(direction == 1 && rates[i].low > rates[i + 2].high + min_gap)
      {
         zone.valid = true;
         zone.direction = 1;
         zone.low = rates[i + 2].high;
         zone.high = rates[i].low;
         zone.start_time = rates[i + 2].time;
         zone.end_time = rates[i].time;
         zone.label = "Bullish FVG";
         return zone;
      }
      if(direction == -1 && rates[i].high < rates[i + 2].low - min_gap)
      {
         zone.valid = true;
         zone.direction = -1;
         zone.low = rates[i].high;
         zone.high = rates[i + 2].low;
         zone.start_time = rates[i + 2].time;
         zone.end_time = rates[i].time;
         zone.label = "Bearish FVG";
         return zone;
      }
   }
   return zone;
}

PriceZone FindLatestOrderBlock(const MqlRates &rates[], int copied, int direction, int min_fvg_points)
{
   PriceZone zone = PriceZoneEmpty();
   for(int i = 1; i < copied - 8; i++)
   {
      bool fvg = false;
      if(direction == 1)
         fvg = rates[i].low > rates[i + 2].high + min_fvg_points * _Point;
      else
         fvg = rates[i].high < rates[i + 2].low - min_fvg_points * _Point;

      if(!fvg)
         continue;

      int ob = FindNearbyOBCandle(rates, copied, i, direction);
      if(ob <= 0)
         continue;

      if(IsMitigated(rates, ob, direction))
         continue;

      zone.valid = true;
      zone.direction = direction;
      zone.low = rates[ob].low;
      zone.high = rates[ob].high;
      zone.start_time = rates[ob].time;
      zone.end_time = rates[i].time;
      zone.label = (direction == 1) ? "Bullish OB" : "Bearish OB";
      return zone;
   }
   return zone;
}

int FindNearbyOBCandle(const MqlRates &rates[], int copied, int fvg_index, int direction)
{
   int max_j = MathMin(copied - 2, fvg_index + 7);
   for(int j = fvg_index + 1; j <= max_j; j++)
   {
      if(direction == 1)
      {
         bool opposite_candle = rates[j].close < rates[j].open;
         bool swept_prev = (j + 1 < copied) ? rates[j].low < rates[j + 1].low : true;
         if(opposite_candle && swept_prev)
            return j;
      }
      else
      {
         bool opposite_candle = rates[j].close > rates[j].open;
         bool swept_prev = (j + 1 < copied) ? rates[j].high > rates[j + 1].high : true;
         if(opposite_candle && swept_prev)
            return j;
      }
   }
   return -1;
}

bool IsMitigated(const MqlRates &rates[], int ob_index, int direction)
{
   for(int i = ob_index - 1; i >= 1; i--)
   {
      if(direction == 1 && rates[i].low <= rates[ob_index].high && rates[i].time > rates[ob_index].time)
         return true;
      if(direction == -1 && rates[i].high >= rates[ob_index].low && rates[i].time > rates[ob_index].time)
         return true;
   }
   return false;
}

bool HasEntryCHOCH(int direction, const MqlRates &rates[], int copied)
{
   int high_a = -1, high_b = -1;
   int low_a = -1, low_b = -1;
   FindLastTwoSwingIndexes(rates, copied, 2, -1, high_a, high_b);
   FindLastTwoSwingIndexes(rates, copied, 2, 1, low_a, low_b);

   if(direction == 1 && high_a > 0)
      return rates[1].close > rates[high_a].high;
   if(direction == -1 && low_a > 0)
      return rates[1].close < rates[low_a].low;

   return false;
}

bool HasFibEMAConfluence(int direction, const MqlRates &rates[], int copied)
{
   double ema21 = GetMA(_Symbol, InpStructureTF, 21, MODE_EMA, 1);
   if(ema21 <= 0.0)
      return false;

   double high = HighestHighFromRates(rates, copied, 80);
   double low = LowestLowFromRates(rates, copied, 80);
   if(high <= low)
      return false;

   double fib50 = low + (high - low) * 0.50;
   double fib618 = low + (high - low) * 0.618;
   double price = rates[1].close;
   double tol = MathMax(GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1) * 0.25, 20.0 * _Point);

   bool near_ema = MathAbs(price - ema21) <= tol || (direction == 1 && rates[1].low <= ema21 && price > ema21) ||
                   (direction == -1 && rates[1].high >= ema21 && price < ema21);
   bool near_fib = MathAbs(price - fib50) <= tol || MathAbs(price - fib618) <= tol;
   return near_ema || near_fib;
}

//+------------------------------------------------------------------+
//| SR level helpers                                                 |
//+------------------------------------------------------------------+
// V6.10: broken levels are retired and selection rewards quality
// (touches and rejection strength) over closeness to the current price.
PriceZone FindSRZone(const MqlRates &rates[], int copied, int direction, double tolerance)
{
   PriceZone best = PriceZoneEmpty();
   double current = rates[1].close;
   double best_score = -1.0e100;
   int depth = MathMax(2, InpStructureSwingDepth);
   int max_i = MathMin(copied - depth - 1, InpSRLookbackBars);

   for(int i = depth + 1; i < max_i; i++)
   {
      bool swing = (direction == 1) ? IsSwingLow(rates, copied, i, depth) : IsSwingHigh(rates, copied, i, depth);
      if(!swing)
         continue;

      double raw_level = (direction == 1) ? rates[i].low : rates[i].high;
      double level = raw_level;
      int touches = 0;
      double cluster_min = raw_level;
      double cluster_max = raw_level;

      if(InpSRSnapLineToWickCluster)
         level = RefineSRClusterLevel(rates, copied, raw_level, direction, tolerance, touches, cluster_min, cluster_max);
      else
         touches = CountTouches(rates, copied, raw_level, direction, tolerance);

      if(direction == 1 && level > current + tolerance)
         continue;
      if(direction == -1 && level < current - tolerance)
         continue;

      if(touches < InpSRMinTouches)
         continue;

      // V6.10: a level that price has decisively closed through is no
      // longer intact support/resistance. Retire it here so it stops
      // being drawn and traded as if it still held.
      if(LevelInvalidated(rates, copied, level, direction))
         continue;

      double distance = MathAbs(current - level);
      double reaction_score = SRReactionScore(rates, copied, level, direction, tolerance);
      double recency_score = 100.0 / (double)(i + 3);
      double distance_penalty = distance / MathMax(tolerance, _Point);

      // V6.20 touch decay: a level hammered too many times is being eaten,
      // not respected. Quality peaks around 2-4 touches, then fades.
      int decay_after = MathMax(2, InpSRTouchDecayAfter);
      double touch_score = MathMin(touches, decay_after) * 12.0 -
                           MathMax(0, touches - decay_after) * MathMax(0.0, InpSRTouchDecayPenalty);

      // V6.20 HTF confluence: a standalone M15 level with no H4 structure
      // behind it is retail noise and is penalized (or blocked, if enabled).
      bool htf_backed = HasHTFLevelNear(level);
      if(InpRequireHTFConfluence && !htf_backed)
         continue;
      double htf_score = htf_backed ? MathMax(0.0, InpHTFConfluenceBonus)
                                    : -MathMax(0.0, InpHTFMissingPenalty);

      double score = touch_score + htf_score + reaction_score + recency_score * 0.35 - distance_penalty * 0.5;

      if(score > best_score)
      {
         best_score = score;
         best.valid = true;
         best.direction = direction;
         double display_width = GetSRDisplayZoneWidth(tolerance, cluster_min, cluster_max);
         best.low = level - display_width;
         best.high = level + display_width;
         best.touches = touches;
         best.start_time = rates[i].time;
         best.end_time = rates[1].time;
         best.label = (direction == 1) ? "Support Zone" : "Resistance Zone";
      }
   }

   return best;
}

int CountTouches(const MqlRates &rates[], int copied, double level, int direction, double tolerance)
{
   int touches = 0;
   bool previous_touch = false;
   int max_i = MathMin(copied - 1, InpSRLookbackBars);
   for(int i = 1; i < max_i; i++)
   {
      bool touch = false;
      if(direction == 1)
         touch = MathAbs(rates[i].low - level) <= tolerance || (rates[i].low <= level + tolerance && rates[i].close > level);
      else
         touch = MathAbs(rates[i].high - level) <= tolerance || (rates[i].high >= level - tolerance && rates[i].close < level);

      if(touch && !previous_touch)
         touches++;
      previous_touch = touch;
   }
   return touches;
}

double RefineSRClusterLevel(const MqlRates &rates[],
                            int copied,
                            double seed_level,
                            int direction,
                            double tolerance,
                            int &touches,
                            double &cluster_min,
                            double &cluster_max)
{
   touches = 0;
   cluster_min = seed_level;
   cluster_max = seed_level;

   double weighted_sum = 0.0;
   double weight_total = 0.0;
   bool previous_touch = false;
   int max_i = MathMin(copied - 1, InpSRLookbackBars);

   for(int i = 1; i < max_i; i++)
   {
      double wick_level = (direction == 1) ? rates[i].low : rates[i].high;
      bool touch = MathAbs(wick_level - seed_level) <= tolerance;

      if(!touch)
      {
         if(direction == 1)
            touch = rates[i].low <= seed_level + tolerance && rates[i].close > seed_level;
         else
            touch = rates[i].high >= seed_level - tolerance && rates[i].close < seed_level;
      }

      if(!touch)
      {
         previous_touch = false;
         continue;
      }

      double recency_weight = 1.0 + (double)(max_i - i) / (double)max_i;
      double rejection_weight = 1.0 + MathMin(2.0, MathAbs(rates[i].close - wick_level) / MathMax(CandleRange(rates[i]), _Point));
      double weight = recency_weight * rejection_weight;

      weighted_sum += wick_level * weight;
      weight_total += weight;
      cluster_min = MathMin(cluster_min, wick_level);
      cluster_max = MathMax(cluster_max, wick_level);

      if(!previous_touch)
         touches++;
      previous_touch = true;
   }

   if(weight_total <= 0.0)
      return seed_level;

   return NormalizePrice(weighted_sum / weight_total);
}

double SRReactionScore(const MqlRates &rates[], int copied, double level, int direction, double tolerance)
{
   double score = 0.0;
   int max_i = MathMin(copied - 1, InpSRLookbackBars);
   for(int i = 1; i < max_i; i++)
   {
      bool reacted = false;
      if(direction == 1)
         reacted = rates[i].low <= level + tolerance && rates[i].close > level;
      else
         reacted = rates[i].high >= level - tolerance && rates[i].close < level;

      if(!reacted)
         continue;

      double wick_rejection = MathAbs(rates[i].close - ((direction == 1) ? rates[i].low : rates[i].high));
      score += MathMin(4.0, wick_rejection / MathMax(CandleRange(rates[i]), _Point) * 4.0);
   }
   return score;
}

double GetSRDisplayZoneWidth(double search_tolerance, double cluster_min, double cluster_max)
{
   double cluster_width = MathAbs(cluster_max - cluster_min) * 0.5;
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   double atr_width = (atr > 0.0) ? atr * 0.08 : 0.0;
   double configured_width = search_tolerance * ClampDouble(InpSRDisplayZoneMultiplier, 0.10, 1.00);
   double width = MathMax(cluster_width, MathMax(atr_width, configured_width));
   return MathMax(width, 10.0 * _Point);
}

double GetSRZoneTolerance()
{
   double fixed_zone = InpSRZoneTolerancePoints * _Point;
   if(!InpSRUseATRZone)
      return fixed_zone;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return fixed_zone;

   return MathMax(10.0 * _Point, atr * InpSRATRZoneMultiplier);
}

//+------------------------------------------------------------------+
//| Supply/demand and custom S/R helpers                             |
//+------------------------------------------------------------------+
void RefreshSupplyDemandZones()
{
   g_sd_zone_count = 0;
   for(int i = 0; i < MAX_SD_ZONES; i++)
      g_sd_zones[i] = PriceZoneEmpty();

   if(!InpEnableSupplyDemandZones)
      return;

   ScanSupplyDemandOnTF(InpSupplyDemandHTF);
   ScanSupplyDemandOnTF(InpSupplyDemandITF);
   ScanSupplyDemandOnTF(InpSupplyDemandLTF);
   g_last_sd_scan_time = TimeCurrent();
}

void ScanSupplyDemandOnTF(ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, InpSDLookbackBars + 30, rates);
   if(copied < 80)
      return;

   int depth = MathMax(2, InpStructureSwingDepth);
   int max_i = MathMin(copied - depth - 2, InpSDLookbackBars);
   double atr = GetATR(_Symbol, tf, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      atr = GetSRZoneTolerance();
   double fuzz = MathMax(10.0 * _Point, atr * MathMax(0.10, InpSDFuzzFactor) * 0.5);
   double current = rates[1].close;

   for(int i = depth + 2; i < max_i && g_sd_zone_count < MAX_SD_ZONES; i++)
   {
      if(IsSwingHigh(rates, copied, i, depth))
      {
         double hi = rates[i].high + fuzz;
         double body_top = MathMax(rates[i].open, rates[i].close);
         double lo = MathMax(MathMin(body_top, rates[i].high - fuzz), rates[i].high - 2.0 * fuzz);
         AddSupplyDemandCandidate(rates, copied, i, -1, lo, hi, tf, current);
      }

      if(IsSwingLow(rates, copied, i, depth))
      {
         double lo = rates[i].low - fuzz;
         double body_bottom = MathMin(rates[i].open, rates[i].close);
         double hi = MathMin(MathMax(body_bottom, rates[i].low + fuzz), rates[i].low + 2.0 * fuzz);
         AddSupplyDemandCandidate(rates, copied, i, 1, lo, hi, tf, current);
      }
   }
}

void AddSupplyDemandCandidate(const MqlRates &rates[],
                              int copied,
                              int origin_index,
                              int original_direction,
                              double low,
                              double high,
                              ENUM_TIMEFRAMES tf,
                              double current)
{
   if(high <= low)
      return;

   int touches = CountZoneTestsAfterIndex(rates, copied, origin_index, low, high);
   bool broken = ZoneBrokenAfterIndex(rates, origin_index, low, high, original_direction);
   bool retested = ZoneRetestedAfterBreak(rates, origin_index, low, high, original_direction);
   int direction = original_direction;

   if(high < current)
      direction = 1;
   else if(low > current)
      direction = -1;

   int strength = ZONE_WEAK;
   if(direction != original_direction || (broken && retested))
      strength = ZONE_TURNCOAT;
   else if(touches > 3)
      strength = ZONE_PROVEN;
   else if(touches > 0)
      strength = ZONE_VERIFIED;
   else if(IsSwingHigh(rates, copied, origin_index, MathMax(3, InpStructureSwingDepth + 2)) ||
           IsSwingLow(rates, copied, origin_index, MathMax(3, InpStructureSwingDepth + 2)))
      strength = ZONE_UNTESTED;

   if(strength < MathMax(0, InpSDMinStrength) && strength != ZONE_TURNCOAT)
      return;

   PriceZone zone = PriceZoneEmpty();
   zone.valid = true;
   zone.direction = direction;
   zone.low = NormalizePrice(low);
   zone.high = NormalizePrice(high);
   zone.touches = touches;
   zone.strength = strength;
   zone.broken = broken;
   zone.retested = retested;
   zone.timeframe = tf;
   zone.start_time = rates[origin_index].time;
   zone.end_time = rates[1].time;
   zone.label = SupplyDemandLabel(zone);

   MergeSupplyDemandZone(zone);
}

void MergeSupplyDemandZone(PriceZone &zone)
{
   for(int i = 0; i < g_sd_zone_count; i++)
   {
      if(g_sd_zones[i].direction != zone.direction)
         continue;
      bool overlaps = zone.low <= g_sd_zones[i].high && zone.high >= g_sd_zones[i].low;
      if(!overlaps)
         continue;

      g_sd_zones[i].low = MathMin(g_sd_zones[i].low, zone.low);
      g_sd_zones[i].high = MathMax(g_sd_zones[i].high, zone.high);
      g_sd_zones[i].touches += zone.touches;
      g_sd_zones[i].strength = MathMax(g_sd_zones[i].strength, zone.strength);
      g_sd_zones[i].broken = g_sd_zones[i].broken || zone.broken;
      g_sd_zones[i].retested = g_sd_zones[i].retested || zone.retested;
      if(zone.start_time > g_sd_zones[i].start_time)
         g_sd_zones[i].start_time = zone.start_time;
      g_sd_zones[i].label = SupplyDemandLabel(g_sd_zones[i]);
      return;
   }

   if(g_sd_zone_count < MAX_SD_ZONES)
   {
      g_sd_zones[g_sd_zone_count] = zone;
      g_sd_zone_count++;
   }
}

int CountZoneTestsAfterIndex(const MqlRates &rates[], int copied, int origin_index, double low, double high)
{
   int touches = 0;
   int last_touch = -1000;
   for(int i = origin_index - 1; i >= 1; i--)
   {
      bool touched = rates[i].low <= high && rates[i].high >= low;
      if(touched && MathAbs(last_touch - i) > 8)
      {
         touches++;
         last_touch = i;
      }
   }
   return touches;
}

bool ZoneBrokenAfterIndex(const MqlRates &rates[], int origin_index, double low, double high, int direction)
{
   int busts = 0;
   for(int i = origin_index - 1; i >= 1; i--)
   {
      if(direction == 1 && rates[i].close < low)
         busts++;
      if(direction == -1 && rates[i].close > high)
         busts++;
      if(busts > 1)
         return true;
   }
   return false;
}

bool ZoneRetestedAfterBreak(const MqlRates &rates[], int origin_index, double low, double high, int direction)
{
   bool broke = false;
   for(int i = origin_index - 1; i >= 1; i--)
   {
      if(direction == 1 && rates[i].close < low)
         broke = true;
      if(direction == -1 && rates[i].close > high)
         broke = true;

      if(!broke)
         continue;

      bool retested = rates[i].low <= high && rates[i].high >= low;
      if(retested)
         return true;
   }
   return false;
}

string SupplyDemandLabel(const PriceZone &zone)
{
   string side = (zone.direction == 1) ? "Demand" : "Supply";
   string strength = "Weak";
   if(zone.strength == ZONE_TURNCOAT) strength = "Turncoat";
   if(zone.strength == ZONE_UNTESTED) strength = "Untested";
   if(zone.strength == ZONE_VERIFIED) strength = "Verified";
   if(zone.strength == ZONE_PROVEN) strength = "Proven";
   return side + " " + strength + " " + TimeframeToText(zone.timeframe);
}

string TimeframeToText(ENUM_TIMEFRAMES tf)
{
   string text = EnumToString(tf);
   StringReplace(text, "PERIOD_", "");
   return text;
}

bool FindSupplyDemandConfluence(int direction,
                                double entry,
                                const PriceZone &support,
                                const PriceZone &resistance,
                                PriceZone &out_zone)
{
   out_zone = PriceZoneEmpty();
   if(!InpEnableSupplyDemandZones || g_sd_zone_count <= 0)
      return false;

   PriceZone active = (direction == 1) ? support : resistance;
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   double extra = MathMax(GetSRZoneTolerance(), atr > 0.0 ? atr * InpSDNearZoneATR : GetSRZoneTolerance());
   double best_score = -1.0e100;

   for(int i = 0; i < g_sd_zone_count; i++)
   {
      PriceZone zone = g_sd_zones[i];
      if(!zone.valid || zone.direction != direction)
         continue;
      if(zone.broken && zone.strength != ZONE_TURNCOAT)
         continue;

      bool price_near = entry >= zone.low - extra && entry <= zone.high + extra;
      bool zone_near = !active.valid || ZonesOverlapOrNear(active, zone, extra);
      if(!price_near && !zone_near)
         continue;

      double mid = (zone.low + zone.high) * 0.5;
      double distance = MathAbs(entry - mid);
      double score = zone.strength * 20.0 + zone.touches * 4.0 - distance / MathMax(extra, _Point);
      if(score > best_score)
      {
         best_score = score;
         out_zone = zone;
      }
   }

   return out_zone.valid;
}

bool ZonesOverlapOrNear(const PriceZone &a, const PriceZone &b, double extra)
{
   if(!a.valid || !b.valid)
      return false;
   return a.low <= b.high + extra && a.high >= b.low - extra;
}

void ApplySupplyDemandConfluenceToSignal(TradeSignal &signal, bool require_zone)
{
   if(!signal.valid || !InpEnableSupplyDemandZones)
      return;

   double entry = (signal.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   PriceZone empty_zone = PriceZoneEmpty();
   PriceZone sd_zone = PriceZoneEmpty();
   bool has_sd = FindSupplyDemandConfluence(signal.direction, entry, empty_zone, empty_zone, sd_zone);

   if(require_zone && !has_sd)
   {
      EmptySignal(signal);
      return;
   }

   if(!has_sd)
      return;

   signal.score = ClampDouble(signal.score + InpSDConfluenceBonus + sd_zone.strength * 2.0, 0.0, 100.0);
   signal.setup = AppendToken(signal.setup, "SD_Confluence");
   signal.reason = AppendToken(signal.reason, sd_zone.label + " alignment");

   double buffer = GetInitialStopBuffer(InpEntryTF);
   if(signal.direction == 1)
   {
      double sd_sl = NormalizePrice(sd_zone.low - buffer);
      if(signal.sl <= 0.0 || sd_sl < signal.sl)
         signal.sl = sd_sl;
      double sd_tp = OpposingSupplyDemandTarget(1, entry);
      if(sd_tp > entry && (signal.tp <= 0.0 || sd_tp > signal.tp))
         signal.tp = NormalizePrice(sd_tp);
   }
   else
   {
      double sd_sl = NormalizePrice(sd_zone.high + buffer);
      if(signal.sl <= 0.0 || sd_sl > signal.sl)
         signal.sl = sd_sl;
      double sd_tp = OpposingSupplyDemandTarget(-1, entry);
      if(sd_tp > 0.0 && sd_tp < entry && (signal.tp <= 0.0 || sd_tp < signal.tp))
         signal.tp = NormalizePrice(sd_tp);
   }
}

double OpposingSupplyDemandTarget(int direction, double entry)
{
   double target = 0.0;
   for(int i = 0; i < g_sd_zone_count; i++)
   {
      PriceZone zone = g_sd_zones[i];
      if(!zone.valid || zone.direction != -direction)
         continue;

      if(direction == 1)
      {
         double candidate = zone.low;
         if(candidate > entry && (target <= 0.0 || candidate < target))
            target = candidate;
      }
      else
      {
         double candidate = zone.high;
         if(candidate < entry && candidate > 0.0 && (target <= 0.0 || candidate > target))
            target = candidate;
      }
   }
   return target;
}

bool FindNearestSupplyDemandZone(int direction, double price, PriceZone &out_zone)
{
   out_zone = PriceZoneEmpty();
   double best_distance = 1.0e100;
   for(int i = 0; i < g_sd_zone_count; i++)
   {
      PriceZone zone = g_sd_zones[i];
      if(!zone.valid || zone.direction != direction)
         continue;

      double distance = 0.0;
      if(price < zone.low)
         distance = zone.low - price;
      else if(price > zone.high)
         distance = price - zone.high;

      if(distance < best_distance)
      {
         best_distance = distance;
         out_zone = zone;
      }
   }
   return out_zone.valid;
}

void ScanCustomSupportResistance(const MqlRates &rates[], int copied, double tolerance)
{
   ArrayInitialize(g_custom_res_levels, 0.0);
   ArrayInitialize(g_custom_sup_levels, 0.0);

   double highs[];
   double lows[];
   int max_bars = MathMin(copied - 3, MathMax(50, InpCustomSRLookback));
   ArrayResize(highs, max_bars);
   ArrayResize(lows, max_bars);
   int high_count = 0;
   int low_count = 0;
   int depth = MathMax(2, InpStructureSwingDepth);

   for(int i = depth + 1; i < max_bars; i++)
   {
      if(IsSwingHigh(rates, copied, i, depth))
      {
         highs[high_count] = rates[i].high;
         high_count++;
      }
      if(IsSwingLow(rates, copied, i, depth))
      {
         lows[low_count] = rates[i].low;
         low_count++;
      }
   }

   ArrayResize(highs, high_count);
   ArrayResize(lows, low_count);
   if(high_count > 1)
      ArraySort(highs);
   if(low_count > 1)
      ArraySort(lows);

   int max_extremes = MathMax(2, InpCustomSRMaxExtremes);
   double match_tolerance = MathMax(tolerance, InpCustomSRTolerancePips * _Point);

   int high_start = MathMax(0, high_count - max_extremes);
   for(int i = high_count - 1; i >= high_start && g_custom_res_levels[0] <= 0.0; i--)
   {
      for(int j = i - 1; j >= high_start; j--)
      {
         if(MathAbs(highs[i] - highs[j]) <= match_tolerance)
         {
            g_custom_res_levels[0] = NormalizePrice((highs[i] + highs[j]) * 0.5);
            g_custom_res_levels[1] = g_custom_res_levels[0];
            break;
         }
      }
   }

   int low_end = MathMin(low_count, max_extremes);
   for(int i = 0; i < low_end && g_custom_sup_levels[0] <= 0.0; i++)
   {
      for(int j = i + 1; j < low_end; j++)
      {
         if(MathAbs(lows[i] - lows[j]) <= match_tolerance)
         {
            g_custom_sup_levels[0] = NormalizePrice((lows[i] + lows[j]) * 0.5);
            g_custom_sup_levels[1] = g_custom_sup_levels[0];
            break;
         }
      }
   }
}

PriceZone CustomSRZone(int direction, double tolerance)
{
   double level = (direction == 1) ? g_custom_sup_levels[0] : g_custom_res_levels[0];
   if(level <= 0.0)
      return PriceZoneEmpty();

   double width = MathMax(tolerance * 0.35, GetInitialStopBuffer(InpEntryTF) * 0.50);
   PriceZone zone = ZoneFromPrices(direction, level - width, level + width,
                                  direction == 1 ? "Custom Cluster Support" : "Custom Cluster Resistance");
   zone.touches = MathMax(InpSRMinTouches, 2);
   zone.strength = ZONE_VERIFIED;
   return zone;
}

PriceZone FindBrokenRetestedZone(const MqlRates &rates[], int copied, int direction, double tolerance)
{
   PriceZone zone = PriceZoneEmpty();
   int depth = MathMax(2, InpStructureSwingDepth);
   int max_i = MathMin(copied - depth - 2, InpSRLookbackBars);

   for(int i = depth + 2; i < max_i; i++)
   {
      if(direction == 1 && IsSwingHigh(rates, copied, i, depth))
      {
         double level = rates[i].high;
         if(HasCloseBeyondAfterIndex(rates, i, level + tolerance * 0.15, 1) &&
            rates[1].low <= level + tolerance && rates[1].close > level)
         {
            zone = ZoneFromPrices(1, level - tolerance * 0.35, level + tolerance * 0.35, "Resistance Retested As Support");
            zone.retested = true;
            zone.strength = ZONE_TURNCOAT;
            zone.start_time = rates[i].time;
            zone.end_time = rates[1].time;
            return zone;
         }
      }

      if(direction == -1 && IsSwingLow(rates, copied, i, depth))
      {
         double level = rates[i].low;
         if(HasCloseBeyondAfterIndex(rates, i, level - tolerance * 0.15, -1) &&
            rates[1].high >= level - tolerance && rates[1].close < level)
         {
            zone = ZoneFromPrices(-1, level - tolerance * 0.35, level + tolerance * 0.35, "Support Retested As Resistance");
            zone.retested = true;
            zone.strength = ZONE_TURNCOAT;
            zone.start_time = rates[i].time;
            zone.end_time = rates[1].time;
            return zone;
         }
      }
   }

   return zone;
}

bool HasCloseBeyondAfterIndex(const MqlRates &rates[], int origin_index, double level, int direction)
{
   for(int i = origin_index - 1; i >= 2; i--)
   {
      if(direction == 1 && rates[i].close > level)
         return true;
      if(direction == -1 && rates[i].close < level)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Risk, stop, and adaptive management helpers                      |
//+------------------------------------------------------------------+
double GetInitialStopBuffer(ENUM_TIMEFRAMES tf)
{
   double fixed_buffer = MathMax(2.0 * _Point, (double)InpStopLossBufferPoints * _Point);
   if(!InpUseATRStopBuffer)
      return fixed_buffer;

   double atr = GetATR(_Symbol, tf, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return fixed_buffer;

   return MathMax(2.0 * _Point, atr * EffectiveATRStopMultiplier());
}

double EffectiveATRStopMultiplier()
{
   double multiplier = MathMax(0.05, InpATRStopMultiplier);
   double current_atr = GetATR(_Symbol, InpEntryTF, InpTrendATRPeriod, 1);
   double average_atr = GetAverageATR(_Symbol, InpEntryTF, InpTrendATRPeriod, MathMax(20, InpVolatilityATRAvgBars), 1);
   if(current_atr > 0.0 && average_atr > 0.0 && current_atr > average_atr * 1.25)
      multiplier += 0.15;

   double win_rate = OverallWinRate();
   if(win_rate > 0.0 && win_rate < 45.0)
      multiplier += 0.10;
   return multiplier;
}

bool IsXAUUSDRiskProfileSymbol()
{
   if(!InpUseXAUUSDRiskProfile || StringLen(InpXAUUSDSymbolKey) == 0)
      return false;
   return StringFind(_Symbol, InpXAUUSDSymbolKey) >= 0;
}

double EffectiveRiskPercent()
{
   double global_cap = MathMax(0.01, InpMaxRiskPercent);
   if(!IsXAUUSDRiskProfileSymbol())
      return MathMin(MathMax(InpRiskPercent, 0.01), global_cap);

   double profile_cap = MathMin(global_cap, MathMax(0.01, InpXAUUSDMaxRiskPercent));
   return MathMin(MathMax(InpXAUUSDRiskPercent, 0.01), profile_cap);
}

double EffectiveMaxSLPercent()
{
   return IsXAUUSDRiskProfileSymbol() ? InpXAUUSDMaxSLPercent : InpMaxSLPercent;
}

double EffectiveMaxSLATRMultiplier()
{
   return IsXAUUSDRiskProfileSymbol() ? InpXAUUSDMaxSLATRMultiplier : InpMaxSLATRMultiplier;
}

double EffectiveMinimumLotActualRiskCapPercent()
{
   if(IsXAUUSDRiskProfileSymbol())
   {
      double gold_cap = MathMax(0.01, InpXAUUSDMinimumLotMaxActualRiskPercent);
      gold_cap = MathMin(gold_cap, MathMax(0.01, InpXAUUSDMaxRiskPercent));
      return gold_cap;
   }

   // The global maximum remains a hard safety ceiling for all non-XAU symbols.
   return MathMin(MathMax(0.01, InpMinimumLotMaxActualRiskPercent),
                  MathMax(0.01, InpMaxRiskPercent));
}

bool IsMinimumLotRiskCompatible(double minimum_lot_risk)
{
   if(!InpAllowMinimumLotCompatibility || minimum_lot_risk <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return false;

   double actual_risk_percent = minimum_lot_risk * 100.0 / equity;
   return actual_risk_percent <= EffectiveMinimumLotActualRiskCapPercent();
}

bool ApplyStopDistanceCaps(const TradeSignal &signal, double entry, double &sl, double &tp)
{
   g_last_risk_reject_reason = "";
   int direction = signal.direction;
   double max_distance = GetMaximumStopDistance(entry);
   if(max_distance <= 0.0)
      return true;

   double distance = MathAbs(entry - sl);
   if(distance <= max_distance)
      return true;

   // A very high-quality V6 setup keeps its structural stop. Dynamic position sizing,
   // minimum-lot rejection and broker stop validation still remain mandatory afterwards.
   bool elite_setup = InpAllowEliteWideStop &&
                      signal.score >= InpEliteScoreForWideStop;
   double elite_limit = max_distance * MathMax(1.0, InpEliteMaxSLMultiplier);
   if(elite_setup && distance <= elite_limit)
   {
      g_last_risk_reject_reason = "Wide structural SL approved for elite setup score " +
                                  DoubleToString(signal.score, 1) +
                                  "; volume will be reduced to the normal risk budget";
      Print(g_last_risk_reject_reason);
      return true;
   }

   if(InpSkipTradeWhenSLTooWide)
   {
      g_last_risk_reject_reason = "Stop too wide: " + DoubleToString(distance / _Point, 1) +
                                  " points exceeds cap of " + DoubleToString(max_distance / _Point, 1) +
                                  " points (elite setup exception requires score " +
                                  DoubleToString(InpEliteScoreForWideStop, 1) + ")";
      return false;
   }

   sl = NormalizePrice(entry - direction * max_distance);
   double reward = MathAbs(tp - entry);
   double min_reward = max_distance * MathMax(InpMinRiskReward, 1.0);
   if(tp <= 0.0 || reward < min_reward)
      tp = NormalizePrice(entry + direction * max_distance * MathMax(InpDefaultRiskReward, InpMinRiskReward));
   return true;
}

double GetMaximumStopDistance(double entry)
{
   double cap = 0.0;
   if(InpMaxSLPoints > 0)
      cap = InpMaxSLPoints * _Point;
   double max_percent = EffectiveMaxSLPercent();
   if(max_percent > 0.0 && entry > 0.0)
   {
      double percent_cap = entry * max_percent / 100.0;
      cap = (cap > 0.0) ? MathMin(cap, percent_cap) : percent_cap;
   }
   if(InpCapSLToATR)
   {
      // V6.36 fix: the cap must live on the SAME timeframe as the breathing
      // floor (M15). Measuring it on the M2-M5 entry TF made the 1.5-ATR
      // floor exceed the cap and rejected nearly every confirmed entry.
      double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
      if(atr > 0.0)
      {
         double atr_cap = atr * MathMax(0.10, EffectiveMaxSLATRMultiplier());
         cap = (cap > 0.0) ? MathMin(cap, atr_cap) : atr_cap;
      }
   }
   return cap;
}

double CalculateAllowedRiskCash()
{
   double risk_percent = EffectiveRiskPercent();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_base = equity;

   if(InpMaxDrawdownPercent > 0.0)
   {
      double drawdown_reserve = MathMax(balance, equity) * InpMaxDrawdownPercent / 100.0;
      risk_base = MathMax(0.0, equity - drawdown_reserve);
   }

   g_last_volatility_risk_factor = CalculateVolatilityRiskFactor();

   double extra_factor = 1.0;
   // V6.20: when trading is allowed at all inside a news window, risk shrinks.
   int news_state = NewsStateNow();
   if(news_state != 0 && (InpNewsMode == 1 || news_state == 2))
      extra_factor *= ClampDouble(InpNewsReduceRiskFactor, 0.05, 1.0);
   // V6.20: confirmation add-on positions use a reduced budget.
   if(CountOurPositions(_Symbol) > 0)
      extra_factor *= ClampDouble(InpAddOnRiskFactor, 0.10, 1.0);

   return risk_base * risk_percent / 100.0 * g_last_volatility_risk_factor * extra_factor;
}

double CalculateVolatilityRiskFactor()
{
   if(!InpUseVolatilityWeightedRisk)
      return 1.0;

   double current_atr = GetATR(_Symbol, InpEntryTF, InpTrendATRPeriod, 1);
   double average_atr = GetAverageATR(_Symbol, InpEntryTF, InpTrendATRPeriod, MathMax(20, InpVolatilityATRAvgBars), 1);
   if(current_atr <= 0.0 || average_atr <= 0.0 || current_atr <= average_atr)
      return 1.0;

   return ClampDouble(average_atr / current_atr, MathMax(0.05, InpVolatilityRiskMinFactor), 1.0);
}

double GetAverageATR(string symbol, ENUM_TIMEFRAMES tf, int period, int bars, int shift)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double values[];
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(handle, 0, shift, bars, values);
   IndicatorRelease(handle);
   if(copied <= 0)
      return 0.0;

   double sum = 0.0;
   for(int i = 0; i < copied; i++)
      sum += values[i];
   return sum / copied;
}

double NormalizeVolumeDown(double volume)
{
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = min_vol;
   if(volume < min_vol)
      return 0.0;
   volume = MathMin(max_vol, volume);
   volume = MathFloor(volume / step) * step;
   int digits = 2;
   if(step < 0.01) digits = 3;
   if(step < 0.001) digits = 4;
   return NormalizeDouble(volume, digits);
}

void StorePositionRiskState(double original_risk, double initial_tp)
{
   if(!PositionSelect(_Symbol))
      return;
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return;

   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   if(ticket == 0)
      return;

   GlobalVariableSet(PositionRiskKey(ticket), original_risk);
   GlobalVariableSet(PositionPartialKey(ticket), 0.0);

   if(InpUseStagedHistoricalTargets)
   {
      int direction = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp1 = initial_tp;
      double minimum_distance = MathMax(original_risk * MathMax(1.0, InpMinRiskReward), 2.0 * _Point);
      double tp2 = FindNextQualifiedM15Target(direction, entry, minimum_distance, tp1);
      double tp3 = (tp2 > 0.0) ? FindNextQualifiedM15Target(direction, entry, minimum_distance, tp2) : 0.0;
      double runner = (tp3 > 0.0) ? NormalizePrice(tp3 + direction * original_risk *
                                                     MathMax(0.25, InpTPRunnerExtensionRR)) : 0.0;

      GlobalVariableSet(PositionTP1Key(ticket), tp1);
      GlobalVariableSet(PositionTP3Key(ticket), tp3);
      GlobalVariableSet(PositionRunnerTPKey(ticket), runner);
      GlobalVariableSet(PositionTargetStageKey(ticket), 0.0);
   }
}

double GetStoredPositionRisk(ulong ticket)
{
   string key = PositionRiskKey(ticket);
   if(GlobalVariableCheck(key))
      return GlobalVariableGet(key);
   return 0.0;
}

string PositionRiskKey(ulong ticket)
{
   return "SCE312_RISK_" + _Symbol + "_" + (string)InpMagicNumber + "_" + (string)ticket;
}

string PositionPartialKey(ulong ticket)
{
   return "SCE312_PARTIAL_" + _Symbol + "_" + (string)InpMagicNumber + "_" + (string)ticket;
}

string PositionTP1Key(ulong ticket)
{
   return "SCE312_TP1_" + _Symbol + "_" + (string)InpMagicNumber + "_" + (string)ticket;
}

string PositionTP3Key(ulong ticket)
{
   return "SCE312_TP3_" + _Symbol + "_" + (string)InpMagicNumber + "_" + (string)ticket;
}

string PositionRunnerTPKey(ulong ticket)
{
   return "SCE312_TPRUN_" + _Symbol + "_" + (string)InpMagicNumber + "_" + (string)ticket;
}

string PositionTargetStageKey(ulong ticket)
{
   return "SCE312_TPSTAGE_" + _Symbol + "_" + (string)InpMagicNumber + "_" + (string)ticket;
}

bool IsTargetBeyondEntry(int direction, double entry, double target)
{
   return (direction == 1) ? target > entry + _Point : target < entry - _Point;
}

bool IsTargetFurther(int direction, double candidate, double current_target)
{
   if(candidate <= 0.0 || current_target <= 0.0)
      return false;
   return (direction == 1) ? candidate > current_target + _Point : candidate < current_target - _Point;
}

bool HasStagedTargetState(ulong ticket)
{
   return GlobalVariableCheck(PositionTP1Key(ticket)) && GlobalVariableCheck(PositionTargetStageKey(ticket));
}

bool StagedTargetsUsable(ulong ticket)
{
   // If the history contains no genuine TP3, keep the trade protected by the
   // normal ATR trail instead of disabling protection merely because TP1 state
   // was stored.  A staged ladder is usable only when it has a real next target.
   return InpUseStagedHistoricalTargets && HasStagedTargetState(ticket) &&
          GlobalVariableCheck(PositionTP3Key(ticket)) && GlobalVariableGet(PositionTP3Key(ticket)) > 0.0;
}

void EnsureStagedTargetState(ulong ticket, int direction, double entry, double risk, double broker_tp)
{
   if(!InpUseStagedHistoricalTargets || HasStagedTargetState(ticket) || risk <= 0.0 ||
      !IsTargetBeyondEntry(direction, entry, broker_tp))
      return;

   double minimum_distance = MathMax(risk * MathMax(1.0, InpMinRiskReward), 2.0 * _Point);
   double tp1 = broker_tp;
   double tp2 = FindNextQualifiedM15Target(direction, entry, minimum_distance, tp1);
   double tp3 = (tp2 > 0.0) ? FindNextQualifiedM15Target(direction, entry, minimum_distance, tp2) : 0.0;
   double runner = (tp3 > 0.0) ? NormalizePrice(tp3 + direction * risk *
                                                  MathMax(0.25, InpTPRunnerExtensionRR)) : 0.0;

   GlobalVariableSet(PositionTP1Key(ticket), tp1);
   GlobalVariableSet(PositionTP3Key(ticket), tp3);
   GlobalVariableSet(PositionRunnerTPKey(ticket), runner);
   GlobalVariableSet(PositionTargetStageKey(ticket), 0.0);
}

bool TargetProgressReached(int direction, double entry, double current, double target, double percent)
{
   if(!IsTargetBeyondEntry(direction, entry, target))
      return false;
   double travelled = (current - entry) * direction;
   double required = (target - entry) * direction * ClampDouble(percent, 1.0, 99.0) / 100.0;
   return travelled >= required;
}

bool TargetHasBeenPassed(int direction, double current, double target)
{
   return (direction == 1) ? current >= target : current <= target;
}

void ManageStagedHistoricalTargets()
{
   if(!InpUseStagedHistoricalTargets)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      int direction = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double current = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double risk = GetStoredPositionRisk(ticket);
      if(risk <= 0.0)
         risk = MathAbs(entry - sl);
      if(risk <= 0.0)
         continue;

      EnsureStagedTargetState(ticket, direction, entry, risk, tp);
      if(!HasStagedTargetState(ticket))
         continue;
      if(!StagedTargetsUsable(ticket))
         continue;

      double tp1 = GlobalVariableGet(PositionTP1Key(ticket));
      double tp3 = GlobalVariableGet(PositionTP3Key(ticket));
      double runner = GlobalVariableGet(PositionRunnerTPKey(ticket));
      int stage = (int)GlobalVariableGet(PositionTargetStageKey(ticket));
      double new_sl = sl;
      double new_tp = tp;
      int next_stage = stage;
      bool modify = false;

      // TP1 is the initial broker target.  To let an exceptional trend continue,
      // the target is extended while there is still room before TP1 is reached.
      // V6.10: extensions also require M15 structure on their side, so a
      // last-gasp momentum reading at the top can no longer keep pushing
      // the target away from a tiring move.
      if(stage == 0 && IsTargetFurther(direction, tp3, tp1) &&
         TargetProgressReached(direction, entry, current, tp1, InpTargetExtensionTriggerPercent) &&
         MomentumStillFavorable(direction) &&
         GetResponsiveStructureTrend(InpStructureTF) == direction)
      {
         new_tp = tp3;
         next_stage = 1;
         modify = true;
      }

      // Once the target that was deliberately extended through is passed, that
      // exact price becomes the protected stop.  This is symmetrical for buys/sells.
      if(next_stage >= 1 && TargetHasBeenPassed(direction, current, tp1) &&
         StopImproves(direction, new_sl, tp1))
      {
         new_sl = NormalizePrice(tp1);
         modify = true;
      }

      if(next_stage == 1 && IsTargetFurther(direction, runner, tp3) &&
         TargetProgressReached(direction, entry, current, tp3, InpTargetExtensionTriggerPercent) &&
         MomentumStillFavorable(direction) &&
         GetResponsiveStructureTrend(InpStructureTF) == direction)
      {
         new_tp = runner;
         next_stage = 2;
         modify = true;
      }

      if(next_stage >= 2 && TargetHasBeenPassed(direction, current, tp3) &&
         StopImproves(direction, new_sl, tp3))
      {
         new_sl = NormalizePrice(tp3);
         modify = true;
      }

      if(!modify)
         continue;

      EnsureValidStops(direction, current, new_sl, new_tp);
      if(trade.PositionModify(ticket, new_sl, new_tp))
      {
         if(next_stage != stage)
         {
            GlobalVariableSet(PositionTargetStageKey(ticket), next_stage);
            string action = (next_stage == 1) ? "TP1 extended to TP3 on sustained momentum" :
                                                 "TP3 extended to final 2R runner on sustained momentum";
            LogJournal("MANAGE", ticket, _Symbol, DirectionToText(direction), PositionGetDouble(POSITION_VOLUME),
                       entry, current, new_sl, new_tp, ExpandStrategyFromComment(PositionGetString(POSITION_COMMENT)),
                       "TARGET_EXTENDED", PositionGetDouble(POSITION_PROFIT), action,
                       "Passed levels are converted into protected stops",
                       "Staged target state advanced without tightening the stop between target levels", MemorySummary());
            if(InpDrawVisuals && InpShowHistoricalTPTargets)
            {
               DeleteObjectsByPrefix("SCE312_VIS_Historical_");
               DrawHistoricalTPTargets();
               ChartRedraw(0);
            }
         }
      }
   }
}

bool PositionPartialTaken(ulong ticket)
{
   string key = PositionPartialKey(ticket);
   return GlobalVariableCheck(key) && GlobalVariableGet(key) > 0.5;
}

void MarkPositionPartialTaken(ulong ticket)
{
   GlobalVariableSet(PositionPartialKey(ticket), 1.0);
}

bool ClosePartialPosition(ulong ticket, double current_volume)
{
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double partial = NormalizeVolumeDown(current_volume * ClampDouble(InpPartialClosePercent, 1.0, 95.0) / 100.0);
   if(partial < min_vol)
      return false;

   if(current_volume - partial < min_vol)
   {
      partial = NormalizeVolumeDown(current_volume - min_vol);
      if(partial < min_vol)
         return false;
   }

   return trade.PositionClosePartial(ticket, partial, (ulong)InpMaxSlippagePoints);
}

double BreakEvenCostBuffer(double atr)
{
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double fixed_buffer = MathMax(0.0, InpBreakEvenBufferPoints * _Point);
   double volatility_buffer = MathMax(0.0, atr * InpBreakEvenATRBufferMultiplier);
   return MathMax(fixed_buffer, spread + volatility_buffer);
}

double GradualStopCandidate(int direction, double old_sl, double raw_candidate, double atr)
{
   if(old_sl <= 0.0 || atr <= 0.0 || InpTrailTightenStepATR <= 0.0)
      return raw_candidate;

   double step = atr * InpTrailTightenStepATR;
   if(direction == 1)
      return MathMin(raw_candidate, old_sl + step);
   return MathMax(raw_candidate, old_sl - step);
}

double EffectiveTrailStartRR()
{
   double value = InpTrailStartRR;
   double win_rate = OverallWinRate();
   if(win_rate >= 58.0)
      value -= 0.10;
   else if(win_rate > 0.0 && win_rate < 45.0)
      value += 0.15;
   return ClampDouble(value, 0.20, 3.00);
}

double EffectiveTrailATRMultiplier()
{
   double value = InpTrailATRMultiplier;
   double win_rate = OverallWinRate();
   if(win_rate >= 58.0)
      value += 0.25;
   else if(win_rate > 0.0 && win_rate < 45.0)
      value = MathMax(0.75, value - 0.15);
   return MathMax(0.25, value);
}

double EffectiveSoftExitMinimumRR()
{
   double value = InpSoftExitMinimumRR;
   double win_rate = OverallWinRate();
   if(win_rate >= 58.0)
      value += 0.10;
   else if(win_rate > 0.0 && win_rate < 45.0)
      value = MathMax(0.10, value - 0.10);
   return ClampDouble(value, 0.05, 2.00);
}

double OverallWinRate()
{
   int trades = 0;
   int wins = 0;
   for(int i = 0; i < STRATEGY_COUNT; i++)
   {
      trades += g_strategy_trades[i];
      wins += g_strategy_wins[i];
   }
   if(trades < InpLearningMinTrades)
      return 0.0;
   return (double)wins * 100.0 / (double)trades;
}

bool ConsecutiveClosesBeyond(const MqlRates &rates[], int copied, double level, int bars, int direction)
{
   if(copied < bars + 2)
      return false;

   for(int i = 1; i <= bars; i++)
   {
      if(direction == 1 && rates[i].close <= level)
         return false;
      if(direction == -1 && rates[i].close >= level)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Trendline helpers                                                |
//+------------------------------------------------------------------+
bool BuildThreePointTrendLine(ENUM_TIMEFRAMES tf, int line_type, TrendLine &line)
{
   line.valid = false;
   line.t1 = 0;
   line.t2 = 0;
   line.p1 = 0.0;
   line.p2 = 0.0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, 260, rates);
   if(copied < 120)
      return false;

   int idx[3];
   int found = 0;
   int depth = MathMax(2, InpTrendSwingDepth);
   for(int i = depth + 1; i < copied - depth && found < 3; i++)
   {
      bool swing = (line_type == -1) ? IsSwingHigh(rates, copied, i, depth) : IsSwingLow(rates, copied, i, depth);
      if(swing)
      {
         idx[found] = i;
         found++;
      }
   }

   if(found < 3)
      return false;

   double recent = (line_type == -1) ? rates[idx[0]].high : rates[idx[0]].low;
   double middle = (line_type == -1) ? rates[idx[1]].high : rates[idx[1]].low;
   double older = (line_type == -1) ? rates[idx[2]].high : rates[idx[2]].low;

   if(line_type == -1)
   {
      if(!(older > middle && middle > recent))
         return false;
      line.t1 = rates[idx[2]].time;
      line.p1 = older;
      line.t2 = rates[idx[0]].time;
      line.p2 = recent;
   }
   else
   {
      if(!(older < middle && middle < recent))
         return false;
      line.t1 = rates[idx[2]].time;
      line.p1 = older;
      line.t2 = rates[idx[0]].time;
      line.p2 = recent;
   }

   line.valid = true;
   return true;
}

double ProjectTrendLine(const TrendLine &line, datetime target_time)
{
   if(!line.valid || line.t2 == line.t1)
      return 0.0;
   return ProjectLine(line.t1, line.p1, line.t2, line.p2, target_time);
}

double ProjectLine(datetime t1, double p1, datetime t2, double p2, datetime target_time)
{
   long dt = (long)t2 - (long)t1;
   if(dt == 0)
      return p2;
   double slope = (p2 - p1) / (double)dt;
   return p1 + slope * (double)((long)target_time - (long)t1);
}

bool ThreeCandleBreak(const MqlRates &rates[], int copied, double level, int direction)
{
   int bars = MathMax(1, InpTrendBreakConfirmCandles);
   if(copied < bars + 2 || level <= 0.0)
      return false;

   for(int i = 1; i <= bars; i++)
   {
      if(direction == 1 && rates[i].close <= level)
         return false;
      if(direction == -1 && rates[i].close >= level)
         return false;
      if(InpTrendRequireStrongBodies && BodyRatio(rates[i]) < 0.50)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Candlestick formulas                                             |
//+------------------------------------------------------------------+
double BodySize(const MqlRates &bar) { return MathAbs(bar.close - bar.open); }
double CandleRange(const MqlRates &bar) { return MathMax(bar.high - bar.low, _Point); }
double UpperShadow(const MqlRates &bar) { return bar.high - MathMax(bar.open, bar.close); }
double LowerShadow(const MqlRates &bar) { return MathMin(bar.open, bar.close) - bar.low; }
double BodyRatio(const MqlRates &bar) { return BodySize(bar) / CandleRange(bar); }

bool IsBullishPinBar(const MqlRates &bar)
{
   double range = CandleRange(bar);
   double body = MathMax(BodySize(bar), _Point);
   return LowerShadow(bar) >= 2.0 * body &&
          UpperShadow(bar) <= 0.10 * range &&
          bar.close > bar.low + 0.70 * range;
}

bool IsBearishPinBar(const MqlRates &bar)
{
   double range = CandleRange(bar);
   double body = MathMax(BodySize(bar), _Point);
   return UpperShadow(bar) >= 2.0 * body &&
          LowerShadow(bar) <= 0.10 * range &&
          bar.close < bar.low + 0.30 * range;
}

bool IsBullishEngulfing(const MqlRates &rates[], int index)
{
   int prev = index + 1;
   return rates[prev].close < rates[prev].open &&
          rates[index].close > rates[index].open &&
          rates[index].close >= rates[prev].open &&
          rates[index].open <= rates[prev].close;
}

bool IsBearishEngulfing(const MqlRates &rates[], int index)
{
   int prev = index + 1;
   return rates[prev].close > rates[prev].open &&
          rates[index].close < rates[index].open &&
          rates[index].close <= rates[prev].open &&
          rates[index].open >= rates[prev].close;
}

bool IsInsideBar(const MqlRates &rates[], int index)
{
   int mother = index + 1;
   return rates[index].high < rates[mother].high && rates[index].low > rates[mother].low;
}

bool IsBullishInsideFalseBreak(const MqlRates &rates[])
{
   return rates[2].high < rates[3].high &&
          rates[2].low > rates[3].low &&
          rates[1].low < rates[3].low &&
          rates[0].close > rates[3].low;
}

bool IsBearishInsideFalseBreak(const MqlRates &rates[])
{
   return rates[2].high < rates[3].high &&
          rates[2].low > rates[3].low &&
          rates[1].high > rates[3].high &&
          rates[0].close < rates[3].high;
}

bool HasBullishCandlePattern(const MqlRates &rates[])
{
   return IsBullishPinBar(rates[1]) ||
          IsBullishEngulfing(rates, 1) ||
          IsBullishInsideFalseBreak(rates);
}

bool HasBearishCandlePattern(const MqlRates &rates[])
{
   return IsBearishPinBar(rates[1]) ||
          IsBearishEngulfing(rates, 1) ||
          IsBearishInsideFalseBreak(rates);
}

bool HasBullishCandlePatternOnTF(ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, tf, 0, 8, rates) < 5)
      return false;
   return HasBullishCandlePattern(rates);
}

bool HasBearishCandlePatternOnTF(ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, tf, 0, 8, rates) < 5)
      return false;
   return HasBearishCandlePattern(rates);
}

//+------------------------------------------------------------------+
//| Indicator wrappers (keep as in previous version)                 |
//+------------------------------------------------------------------+
double GetMA(string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_MA_METHOD method, int shift)
{
   int handle = iMA(symbol, tf, period, 0, method, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return 0.0;
   double buffer[];
   ArraySetAsSeries(buffer, true);
   int copied = CopyBuffer(handle, 0, shift, 1, buffer);
   IndicatorRelease(handle);
   if(copied != 1)
      return 0.0;
   return buffer[0];
}

double GetRSI(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int handle = iRSI(symbol, tf, period, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return 50.0;
   double buffer[];
   ArraySetAsSeries(buffer, true);
   int copied = CopyBuffer(handle, 0, shift, 1, buffer);
   IndicatorRelease(handle);
   if(copied != 1)
      return 50.0;
   return buffer[0];
}

double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return 0.0;
   double buffer[];
   ArraySetAsSeries(buffer, true);
   int copied = CopyBuffer(handle, 0, shift, 1, buffer);
   IndicatorRelease(handle);
   if(copied != 1)
      return 0.0;
   return buffer[0];
}

bool GetMACD(string symbol, ENUM_TIMEFRAMES tf, int shift, double &main_value, double &signal_value)
{
   main_value = 0.0;
   signal_value = 0.0;
   int handle = iMACD(symbol, tf, InpTrendMACDFast, InpTrendMACDSlow, InpTrendMACDSignal, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return false;
   double main_buffer[];
   double signal_buffer[];
   ArraySetAsSeries(main_buffer, true);
   ArraySetAsSeries(signal_buffer, true);
   int copied_main = CopyBuffer(handle, 0, shift, 1, main_buffer);
   int copied_sig = CopyBuffer(handle, 1, shift, 1, signal_buffer);
   IndicatorRelease(handle);
   if(copied_main != 1 || copied_sig != 1)
      return false;
   main_value = main_buffer[0];
   signal_value = signal_buffer[0];
   return true;
}

bool CrossedMA(ENUM_TIMEFRAMES tf, int p1, ENUM_MA_METHOD m1, int p2, ENUM_MA_METHOD m2, int direction)
{
   double fast1 = GetMA(_Symbol, tf, p1, m1, 1);
   double fast2 = GetMA(_Symbol, tf, p1, m1, 2);
   double slow1 = GetMA(_Symbol, tf, p2, m2, 1);
   double slow2 = GetMA(_Symbol, tf, p2, m2, 2);

   if(direction == 1)
      return fast2 <= slow2 && fast1 > slow1;
   return fast2 >= slow2 && fast1 < slow1;
}

bool MACDCrossed(ENUM_TIMEFRAMES tf, int direction)
{
   double main1, sig1, main2, sig2;
   if(!GetMACD(_Symbol, tf, 1, main1, sig1))
      return false;
   if(!GetMACD(_Symbol, tf, 2, main2, sig2))
      return false;

   if(direction == 1)
      return main2 <= sig2 && main1 > sig1;
   return main2 >= sig2 && main1 < sig1;
}

//+------------------------------------------------------------------+
//| General helpers                                                  |
//+------------------------------------------------------------------+
void EmptySignal(TradeSignal &s)
{
   s.valid = false;
   s.direction = 0;
   s.score = 0.0;
   s.agreeing_strategies = 0;
   s.strategy = "";
   s.setup = "";
   s.reason = "";
   s.sl = 0.0;
   s.tp = 0.0;
}

PriceZone PriceZoneEmpty()
{
   PriceZone z;
   z.valid = false;
   z.direction = 0;
   z.low = 0.0;
   z.high = 0.0;
   z.touches = 0;
   z.strength = 0;
   z.broken = false;
   z.retested = false;
   z.timeframe = PERIOD_CURRENT;
   z.start_time = 0;
   z.end_time = 0;
   z.label = "";
   return z;
}

PriceZone ZoneFromPrices(int direction, double low, double high, string label)
{
   PriceZone z = PriceZoneEmpty();
   z.valid = true;
   z.direction = direction;
   z.low = MathMin(low, high);
   z.high = MathMax(low, high);
   z.touches = 1;
   z.strength = ZONE_VERIFIED;
   z.broken = false;
   z.retested = false;
   z.timeframe = InpStructureTF;
   z.start_time = TimeCurrent();
   z.end_time = TimeCurrent();
   z.label = label;
   return z;
}

void MergeStrategySignal(const TradeSignal &candidate, TradeSignal &buy, TradeSignal &sell)
{
   if(!candidate.valid)
      return;
   if(candidate.direction == 1 && (!buy.valid || candidate.score > buy.score))
      buy = candidate;
   if(candidate.direction == -1 && (!sell.valid || candidate.score > sell.score))
      sell = candidate;
}

bool PriceInZone(double price, const PriceZone &zone)
{
   return zone.valid && price >= zone.low && price <= zone.high;
}

bool TradingEnvironmentOK()
{
   if(InpMaxSpreadPoints > 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int spread_points = (int)MathRound((ask - bid) / _Point);
      if(spread_points > InpMaxSpreadPoints)
         return false;
   }

   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   return mode == SYMBOL_TRADE_MODE_FULL || mode == SYMBOL_TRADE_MODE_LONGONLY || mode == SYMBOL_TRADE_MODE_SHORTONLY;
}

bool DirectionAllowedForSymbol(int direction)
{
   if(!InpUseBoomCrashDirectionFilter)
      return true;

   string symbol = _Symbol;
   StringToLower(symbol);

   if(StringFind(symbol, "boom") >= 0 && direction != 1)
      return false;
   if(StringFind(symbol, "crash") >= 0 && direction != -1)
      return false;

   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_LONGONLY && direction != 1)
      return false;
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY && direction != -1)
      return false;

   return true;
}

int CountOurPositions(string symbol)
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      count++;
   }
   return count;
}

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &storage)
{
   datetime current = iTime(_Symbol, tf, 0);
   if(current <= 0)
      return false;
   if(current != storage)
   {
      storage = current;
      return true;
   }
   return false;
}

datetime StartOfDay(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

double NormalizePrice(double price) { return NormalizeDouble(price, _Digits); }
double NormalizeVolume(double volume)
{
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = min_vol;
   volume = MathMax(min_vol, MathMin(max_vol, volume));
   volume = MathFloor(volume / step) * step;
   int digits = 2;
   if(step < 0.01) digits = 3;
   if(step < 0.001) digits = 4;
   return NormalizeDouble(volume, digits);
}
double ClampDouble(double value, double low, double high) { return MathMax(low, MathMin(high, value)); }
string AppendToken(string current, string token)
{
   if(token == "")
      return current;
   if(current == "")
      return token;
   return current + " + " + token;
}

int StrategyAgreementCount(string strategy)
{
   int count = 0;
   for(int i = 0; i < STRATEGY_COUNT; i++)
   {
      if(StringFind(strategy, g_strategy_names[i]) >= 0)
         count++;
   }
   return count;
}

string CleanCSV(string value)
{
   string out = value;
   StringReplace(out, "\r", " ");
   StringReplace(out, "\n", " ");
   StringReplace(out, ";", ",");
   return out;
}
string DirectionToText(int direction)
{
   if(direction == 1) return "BUY";
   if(direction == -1) return "SELL";
   return "";
}
string BuildTradeComment(string strategy)
{
   string comment = "SCE3|";
   if(StringFind(strategy, "SRBounce") >= 0)
      comment += "+SR";
   if(StringFind(strategy, "TrendFollowing") >= 0)
      comment += "+TR";
   if(StringFind(strategy, "FVGRetest") >= 0)
      comment += "+FVG";
   StringReplace(comment, "|+", "|");
   if(StringLen(comment) > 30)
      comment = StringSubstr(comment, 0, 30);
   return comment;
}
string ExpandStrategyFromComment(string comment)
{
   string strategy = "";
   if(StringFind(comment, "SR") >= 0)
      strategy = AppendToken(strategy, "SRBounce");
   if(StringFind(comment, "TR") >= 0)
      strategy = AppendToken(strategy, "TrendFollowing");
   if(StringFind(comment, "FVG") >= 0)
      strategy = AppendToken(strategy, "FVGRetest");
   if(strategy == "")
      strategy = comment;
   return strategy;
}
string CloseReasonText(long reason, double profit)
{
   if(reason == DEAL_REASON_TP) return "Take profit reached";
   if(reason == DEAL_REASON_SL) return (profit >= 0.0) ? "Trailing stop protected profit" : "Stop loss reached";
   if(reason == DEAL_REASON_SO) return "Stop out";
   if(reason == DEAL_REASON_EXPERT) return "EA adaptive exit";
   if(reason == DEAL_REASON_CLIENT) return "Manual close";
   return "Closed by broker/platform event";
}
string BuildWinLossExplanation(string strategy, int direction, double profit, string close_reason)
{
   if(profit > 0.0)
      return "Won because " + strategy + " aligned with " + DirectionToText(direction) + " momentum and exit logic protected or reached profit. Close reason: " + close_reason;
   if(profit < 0.0)
      return "Lost because price invalidated the selected " + strategy + " setup before target expansion. Close reason: " + close_reason;
   return "Closed near breakeven because the setup did not expand enough after entry. Close reason: " + close_reason;
}
string BuildAdjustmentText(string strategy, double profit)
{
   if(profit > 0.0)
      return "Memory increases trust in " + strategy + " under similar confluence; trailing can extend TP if momentum remains strong";
   if(profit < 0.0)
      return "Memory reduces score for " + strategy + " until more winning samples appear; future trades require stronger confluence";
   return "Memory keeps score neutral and waits for more journal samples";
}
double HighestHigh(string symbol, ENUM_TIMEFRAMES tf, int count, int start)
{
   int index = iHighest(symbol, tf, MODE_HIGH, count, start);
   return (index < 0) ? 0.0 : iHigh(symbol, tf, index);
}
double LowestLow(string symbol, ENUM_TIMEFRAMES tf, int count, int start)
{
   int index = iLowest(symbol, tf, MODE_LOW, count, start);
   return (index < 0) ? 0.0 : iLow(symbol, tf, index);
}
double HighestHighFromRates(const MqlRates &rates[], int copied, int lookback)
{
   int max_i = MathMin(copied - 1, lookback);
   double high = rates[1].high;
   for(int i = 1; i <= max_i; i++)
      high = MathMax(high, rates[i].high);
   return high;
}
double LowestLowFromRates(const MqlRates &rates[], int copied, int lookback)
{
   int max_i = MathMin(copied - 1, lookback);
   double low = rates[1].low;
   for(int i = 1; i <= max_i; i++)
      low = MathMin(low, rates[i].low);
   return low;
}
int ArrayMaximumHigh(const MqlRates &rates[], int lookback)
{
   int idx = 1;
   for(int i = 1; i <= lookback; i++)
      if(rates[i].high > rates[idx].high)
         idx = i;
   return idx;
}
int ArrayMinimumLow(const MqlRates &rates[], int lookback)
{
   int idx = 1;
   for(int i = 1; i <= lookback; i++)
      if(rates[i].low < rates[idx].low)
         idx = i;
   return idx;
}
void GetPreviousDailyLevels(double &pdh, double &pdl)
{
   pdh = 0.0;
   pdl = 0.0;
   MqlRates daily[];
   ArraySetAsSeries(daily, true);
   if(CopyRates(_Symbol, PERIOD_D1, 1, 1, daily) == 1)
   {
      pdh = daily[0].high;
      pdl = daily[0].low;
   }
}

//+------------------------------------------------------------------+
//| V6.10 - Pilot first trade state                                   |
//+------------------------------------------------------------------+
string PilotStageKey()
{
   return "SCE312_PILOT_" + _Symbol + "_" + (string)InpMagicNumber;
}

string PilotTrendKey()
{
   return "SCE312_PILOTDIR_" + _Symbol + "_" + (string)InpMagicNumber;
}

string PilotTimeKey()
{
   return "SCE312_PILOTTIME_" + _Symbol + "_" + (string)InpMagicNumber;
}

int PilotStage()
{
   if(!GlobalVariableCheck(PilotStageKey()))
      return 0;
   return (int)GlobalVariableGet(PilotStageKey());
}

void SetPilotStage(int stage)
{
   GlobalVariableSet(PilotStageKey(), (double)stage);
   GlobalVariableSet(PilotTimeKey(), (double)(long)TimeCurrent());
}

// Stage 0: no pilot for the current trend yet -> next trade is a
//          broker-minimum-lot pilot.
// Stage 1: pilot running or just closed -> waiting for confirmation.
// Stage 2: trend confirmed -> full risk-based sizing is unlocked.
void UpdatePilotTrendState()
{
   if(!InpUsePilotFirstTrade)
      return;

   int trend = GetDealingRangeTrend();
   int stored = GlobalVariableCheck(PilotTrendKey()) ? (int)GlobalVariableGet(PilotTrendKey()) : -999;
   if(trend != stored)
   {
      GlobalVariableSet(PilotTrendKey(), (double)trend);
      SetPilotStage(0);   // a fresh trend always starts with a pilot trade
      return;
   }

   if(PilotStage() != 1)
      return;

   // Confirmation while the pilot is still open: enough open profit
   // proves the trend, so a second, fully sized trade becomes possible
   // as soon as a valid setup appears.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      int direction = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double current = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double risk = GetStoredPositionRisk(ticket);
      if(risk <= 0.0)
         risk = MathAbs(entry - sl);
      if(risk <= 0.0)
         continue;

      double rr = (current - entry) * direction / risk;
      if(rr >= MathMax(0.10, InpPilotConfirmProfitRR))
      {
         SetPilotStage(2);
         return;
      }
   }

   // Timeout so a stale, position-less pilot state cannot block trading.
   double stamp = GlobalVariableCheck(PilotTimeKey()) ? GlobalVariableGet(PilotTimeKey()) : 0.0;
   if(stamp > 0.0 && CountOurPositions(_Symbol) == 0 &&
      (long)TimeCurrent() - (long)stamp > (long)MathMax(4, InpPilotConfirmTimeoutBars) * PeriodSeconds(InpStructureTF))
      SetPilotStage(0);
}

//+------------------------------------------------------------------+
//| V6.10 - Second-retest confirmation helpers                        |
//+------------------------------------------------------------------+
bool HasSecondRetestConfirmation(const MqlRates &rates[], int copied, const PriceZone &zone, int direction)
{
   if(!InpRequireSecondRetest)
      return true;
   if(!zone.valid)
      return false;

   int limit = MathMin(copied - 2, MathMax(12, InpRetestLookbackBars));
   int separation = MathMax(1, InpRetestSeparationBars);
   int touches = 0;
   int last_touch_index = 1000000;

   // Scan oldest to newest so clusters of adjacent touching bars count
   // as one distinct retest.
   for(int i = limit; i >= 1; i--)
   {
      bool touch = (direction == 1) ?
                   (rates[i].low <= zone.high && rates[i].high >= zone.low) :
                   (rates[i].high >= zone.low && rates[i].low <= zone.high);
      if(!touch)
         continue;
      if(last_touch_index - i >= separation)
         touches++;
      last_touch_index = i;
   }

   bool current_bar_is_touch = (direction == 1) ? rates[1].low <= zone.high
                                                : rates[1].high >= zone.low;
   return current_bar_is_touch && touches >= 2;
}

int CountTrendlineTouches(const MqlRates &rates[], int copied,
                          datetime t_old, double p_old, datetime t_new, double p_new,
                          int line_type, double tolerance)
{
   int limit = MathMin(copied - 2, MathMax(12, InpRetestLookbackBars));
   int separation = MathMax(1, InpRetestSeparationBars);
   int touches = 0;
   int last_touch_index = 1000000;

   for(int i = limit; i >= 1; i--)
   {
      double line_price = ProjectLine(t_old, p_old, t_new, p_new, rates[i].time);
      if(line_price <= 0.0)
         continue;
      bool touch = (line_type == 1) ?
                   (rates[i].low <= line_price + tolerance && rates[i].close > line_price - tolerance) :
                   (rates[i].high >= line_price - tolerance && rates[i].close < line_price + tolerance);
      if(!touch)
         continue;
      if(last_touch_index - i >= separation)
         touches++;
      last_touch_index = i;
   }
   return touches;
}

//+------------------------------------------------------------------+
//| V6.10 - SR level invalidation                                     |
//+------------------------------------------------------------------+
bool LevelInvalidated(const MqlRates &rates[], int copied, double level, int direction)
{
   int needed = MathMax(1, InpSRInvalidationCloses);
   int consecutive = 0;
   int limit = MathMin(copied - 1, InpSRLookbackBars);

   // Scan from the newest closed bar backwards. If the most recent
   // closes sit decisively beyond the level, it has failed; a single
   // false-break wick that closed back on the correct side keeps it.
   for(int i = 1; i <= limit; i++)
   {
      bool beyond = (direction == 1) ? rates[i].close < level : rates[i].close > level;
      if(beyond)
      {
         consecutive++;
         if(consecutive >= needed)
            return true;
      }
      else
         return false;
   }
   return false;
}

//+------------------------------------------------------------------+
//| V6.10 - Per-tick profit protection                                |
//+------------------------------------------------------------------+
string PositionPeakKey(ulong ticket)
{
   return "SCE312_PEAK_" + _Symbol + "_" + (string)InpMagicNumber + "_" + (string)ticket;
}

void GuardOpenProfits()
{
   if(!InpUseProfitGivebackGuard && InpProfitLockTriggerPercent <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      int direction = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double current = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double risk = GetStoredPositionRisk(ticket);
      if(risk <= 0.0)
         risk = MathAbs(entry - sl);
      if(risk <= 0.0)
         continue;

      double rr = (current - entry) * direction / risk;

      string peak_key = PositionPeakKey(ticket);
      double peak = GlobalVariableCheck(peak_key) ? GlobalVariableGet(peak_key) : 0.0;
      if(rr > peak)
      {
         peak = rr;
         GlobalVariableSet(peak_key, peak);
      }

      // Profit floor: once price has covered most of the road to TP,
      // the stop is raised to keep a fixed share of the open gain.
      if(InpProfitLockTriggerPercent > 0.0 && tp > 0.0 && IsTargetBeyondEntry(direction, entry, tp))
      {
         double tp_distance = MathAbs(tp - entry);
         double progress = (current - entry) * direction / tp_distance * 100.0;
         if(progress >= ClampDouble(InpProfitLockTriggerPercent, 10.0, 99.0))
         {
            double gain = (current - entry) * direction;
            double floor_sl = entry + direction * gain *
                              ClampDouble(InpProfitLockKeepPercent, 10.0, 90.0) / 100.0;
            if(StopImproves(direction, sl, floor_sl))
            {
               double new_sl = NormalizePrice(floor_sl);
               double new_tp = tp;
               EnsureValidStops(direction, current, new_sl, new_tp);
               if(trade.PositionModify(ticket, new_sl, new_tp))
                  sl = new_sl;
            }
         }
      }

      // Giveback guard: after the trade has reached the arming R multiple,
      // it is never allowed to give back more than the configured share of
      // its peak profit, and it can never round-trip into a loss.
      if(InpUseProfitGivebackGuard && peak >= MathMax(0.25, InpGivebackArmRR))
      {
         double keep_line = peak * (1.0 - ClampDouble(InpMaxProfitGivebackPercent, 10.0, 90.0) / 100.0);
         if(rr <= MathMax(0.05, keep_line))
         {
            LogJournal("MANAGE", ticket, _Symbol, DirectionToText(direction),
                       PositionGetDouble(POSITION_VOLUME), entry, current, sl, tp,
                       ExpandStrategyFromComment(PositionGetString(POSITION_COMMENT)),
                       "PROFIT_PROTECT", PositionGetDouble(POSITION_PROFIT),
                       "profit giveback guard",
                       "Peak open profit reached " + DoubleToString(peak, 2) + "R and " +
                       DoubleToString(InpMaxProfitGivebackPercent, 0) + "% of it was given back",
                       "Winner closed before it could turn into a loss", MemorySummary());
            trade.PositionClose(ticket);
            GlobalVariableDel(peak_key);
         }
      }
   }
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| V6.20 - Anchored dealing-range lock                               |
//+------------------------------------------------------------------+
string RangeHighKey()
{
   return "SCE312_RANGEHI_" + _Symbol + "_" + (string)InpMagicNumber;
}

string RangeLowKey()
{
   return "SCE312_RANGELO_" + _Symbol + "_" + (string)InpMagicNumber;
}

bool LoadLockedDealingRange(DealingRange &range)
{
   if(!GlobalVariableCheck(RangeHighKey()) || !GlobalVariableCheck(RangeLowKey()))
      return false;
   double hi = GlobalVariableGet(RangeHighKey());
   double lo = GlobalVariableGet(RangeLowKey());
   if(hi <= lo || hi <= 0.0 || lo <= 0.0)
      return false;
   range.high = hi;
   range.low = lo;
   range.equilibrium = (hi + lo) * 0.5;
   range.equilibrium_band = MathMax((hi - lo) * MathMax(0.0, InpEquilibriumBandPercent) / 100.0,
                                    5.0 * _Point);
   range.valid = true;
   return true;
}

void StoreLockedDealingRange(const DealingRange &range)
{
   GlobalVariableSet(RangeHighKey(), range.high);
   GlobalVariableSet(RangeLowKey(), range.low);
}

//+------------------------------------------------------------------+
//| V6.20 - OTE zone (62-79% retracement pocket)                      |
//+------------------------------------------------------------------+
bool PriceInOTEZone(int direction, const DealingRange &range, double price)
{
   if(!InpUseOTEZone || !range.valid)
      return false;
   double width = range.high - range.low;
   if(width <= 0.0)
      return false;

   double s = ClampDouble(InpOTEStart, 0.30, 0.95);
   double e = ClampDouble(InpOTEEnd, s + 0.01, 0.99);

   if(direction == 1)
   {
      // A buy retraces down from the range high into the deep discount pocket.
      double zone_top = range.high - width * s;
      double zone_bottom = range.high - width * e;
      return price <= zone_top && price >= zone_bottom;
   }

   // A sell retraces up from the range low into the deep premium pocket.
   double zone_bottom2 = range.low + width * s;
   double zone_top2 = range.low + width * e;
   return price >= zone_bottom2 && price <= zone_top2;
}

//+------------------------------------------------------------------+
//| V6.20 - News filter (NFP)                                         |
//+------------------------------------------------------------------+
bool IsSyntheticIndexSymbol()
{
   string s = _Symbol;
   StringToLower(s);
   return StringFind(s, "volatility") >= 0 || StringFind(s, "boom") >= 0 ||
          StringFind(s, "crash") >= 0 || StringFind(s, "jump") >= 0 ||
          StringFind(s, "step") >= 0 || StringFind(s, "range break") >= 0 ||
          StringFind(s, "drift") >= 0;
}

bool IsNFPDayNow()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.day_of_week == 5 && dt.day <= 7;   // first Friday of the month
}

// Returns 0 = normal, 1 = blackout window, 2 = post-news exploit window.
int NewsStateNow()
{
   if(!InpUseNewsFilter)
      return 0;
   if(InpNewsOnlyRealMarkets && IsSyntheticIndexSymbol())
      return 0;
   if(!IsNFPDayNow())
      return 0;

   MqlDateTime nt;
   TimeToStruct(TimeCurrent(), nt);
   nt.hour = (int)MathMax(0, MathMin(23, InpNewsHourServer));
   nt.min = (int)MathMax(0, MathMin(59, InpNewsMinuteServer));
   nt.sec = 0;
   datetime news_time = StructToTime(nt);

   long diff_min = ((long)TimeCurrent() - (long)news_time) / 60;
   long before = (long)MathMax(0, InpNewsBlockBeforeMin);
   long after = (long)MathMax(0, InpNewsBlockAfterMin);

   if(diff_min >= -before && diff_min <= after)
      return 1;
   if(InpNewsMode == 2 && diff_min > after &&
      diff_min <= after + (long)MathMax(10, InpNewsExploitWindowMin))
      return 2;
   return 0;
}

// The initial NFP spike is untradeable; the edge is the first retest of the
// FVG that the displacement candle left behind, traded in the spike's direction.
bool BuildNewsDisplacementSignal(TradeSignal &signal)
{
   EmptySignal(signal);

   MqlRates m5[];
   ArraySetAsSeries(m5, true);
   int copied = CopyRates(_Symbol, PERIOD_M5, 0, 40, m5);
   if(copied < 12)
      return false;

   double avg_atr = GetAverageATR(_Symbol, PERIOD_M5, InpTrendATRPeriod,
                                  MathMax(20, InpVolatilityATRAvgBars), 1);
   if(avg_atr <= 0.0)
      return false;
   double required = avg_atr * MathMax(0.5, InpNewsDisplacementATR);

   int spike = -1;
   int direction = 0;
   for(int i = 2; i <= MathMin(copied - 3, 18); i++)
   {
      double candle_range = m5[i].high - m5[i].low;
      if(candle_range < required || BodyRatio(m5[i]) < 0.55)
         continue;
      spike = i;
      direction = (m5[i].close > m5[i].open) ? 1 : -1;
      break;
   }
   if(spike < 0 || direction == 0)
      return false;

   double zone_low, zone_high;
   if(direction == 1)
   {
      zone_low = m5[spike + 1].high;
      zone_high = m5[spike - 1].low;
   }
   else
   {
      zone_low = m5[spike - 1].high;
      zone_high = m5[spike + 1].low;
   }
   if(zone_high - zone_low < MathMax(3.0 * _Point, avg_atr * 0.15))
      return false;   // the spike left no meaningful imbalance

   // First retest only - any earlier touch invalidates the setup.
   for(int j = 2; j < spike - 1; j++)
      if(m5[j].low <= zone_high && m5[j].high >= zone_low)
         return false;

   bool touch = m5[1].low <= zone_high && m5[1].high >= zone_low;
   double mid = (zone_low + zone_high) * 0.5;
   bool holds = (direction == 1) ? (m5[1].close > mid) : (m5[1].close < mid);
   bool candle_ok = (direction == 1) ?
                    (HasBullishCandlePattern(m5) ||
                     (m5[1].close > m5[1].open && BodyRatio(m5[1]) >= 0.50)) :
                    (HasBearishCandlePattern(m5) ||
                     (m5[1].close < m5[1].open && BodyRatio(m5[1]) >= 0.50));
   if(!touch || !holds || !candle_ok)
      return false;

   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = MathMax(GetInitialStopBuffer(PERIOD_M5), avg_atr * 0.25);
   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "TrendFollowing";
   signal.setup = (direction == 1) ? "NFP_DisplacementFVG_Buy" : "NFP_DisplacementFVG_Sell";
   signal.reason = "post-news displacement candle, first FVG retest held with a directional close";
   signal.score = 82.0;
   signal.sl = (direction == 1) ? NormalizePrice(MathMin(zone_low, m5[1].low) - buffer)
                                : NormalizePrice(MathMax(zone_high, m5[1].high) + buffer);
   signal.tp = (direction == 1) ? NormalizePrice(entry + MathAbs(entry - signal.sl) * MathMax(InpMinRiskReward, 1.5))
                                : NormalizePrice(entry - MathAbs(signal.sl - entry) * MathMax(InpMinRiskReward, 1.5));
   return signal.sl > 0.0 && signal.tp > 0.0;
}

//+------------------------------------------------------------------+
//| V6.20 - H4 confluence and approach speed                          |
//+------------------------------------------------------------------+
bool HasHTFLevelNear(double level)
{
   static datetime cached_bar = 0;
   static double cached_levels[64];
   static int cached_count = 0;
   static double cached_atr = 0.0;

   datetime h4_bar = iTime(_Symbol, PERIOD_H4, 0);
   if(h4_bar != cached_bar)
   {
      cached_bar = h4_bar;
      cached_count = 0;
      cached_atr = GetATR(_Symbol, PERIOD_H4, InpTrendATRPeriod, 1);
      MqlRates h4[];
      ArraySetAsSeries(h4, true);
      int copied = CopyRates(_Symbol, PERIOD_H4, 0, 320, h4);
      int depth = 2;
      for(int i = depth + 1; i < copied - depth && cached_count < 64; i++)
      {
         if(IsSwingHigh(h4, copied, i, depth))
         {
            cached_levels[cached_count] = h4[i].high;
            cached_count++;
         }
         if(cached_count < 64 && IsSwingLow(h4, copied, i, depth))
         {
            cached_levels[cached_count] = h4[i].low;
            cached_count++;
         }
      }
   }

   if(cached_count <= 0 || cached_atr <= 0.0)
      return true;   // no H4 information available; never punish for missing data

   double tolerance = cached_atr * MathMax(0.10, InpHTFConfluenceATR);
   for(int i = 0; i < cached_count; i++)
      if(MathAbs(cached_levels[i] - level) <= tolerance)
         return true;
   return false;
}

bool IsSlowGrindApproach(const MqlRates &rates[], int copied)
{
   if(!InpUseApproachSpeedFilter)
      return false;
   int bars = MathMax(2, InpApproachBars);
   if(copied < bars + 2)
      return false;
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;

   double total = 0.0;
   for(int i = 1; i <= bars; i++)
      total += rates[i].high - rates[i].low;
   double average = total / bars;
   // A slow, small-bodied grind into a level is absorption - it usually
   // breaks the level. A sharp spike into it is the bounce material.
   return average < atr * MathMax(0.05, InpSlowGrindMaxATRPerBar);
}

//+------------------------------------------------------------------+
//| V6.20 - Market regime detection and routing                       |
//+------------------------------------------------------------------+
int CurrentMarketRegime()
{
   datetime bar = iTime(_Symbol, InpEntryTF, 0);
   if(bar == g_last_regime_bar && g_current_regime != 0)
      return g_current_regime;

   int regime = 2;   // ranging by default
   double current_atr = GetATR(_Symbol, InpEntryTF, InpTrendATRPeriod, 1);
   double average_atr = GetAverageATR(_Symbol, InpEntryTF, InpTrendATRPeriod,
                                      MathMax(20, InpVolatilityATRAvgBars), 1);
   if(current_atr > 0.0 && average_atr > 0.0 &&
      current_atr >= average_atr * MathMax(1.05, InpRegimeExpansionATRFactor))
      regime = 3;   // volatile expansion outranks everything else
   else if(GetDealingRangeTrend() != 0)
      regime = 1;   // trending

   g_current_regime = regime;
   g_last_regime_bar = bar;
   return regime;
}

string RegimeToText(int regime)
{
   if(regime == 1) return "Trending";
   if(regime == 2) return "Ranging";
   if(regime == 3) return "Expansion";
   return "Unknown";
}

int RegimeFromText(string text)
{
   if(StringFind(text, "Trend") >= 0) return 1;
   if(StringFind(text, "Rang") >= 0) return 2;
   if(StringFind(text, "Expan") >= 0) return 3;
   return 0;
}

// Hard-coded routing priors: which setups are allowed to lead in which
// regime, before (and alongside) the per-regime learned statistics.
bool ApplyRegimeRouting(TradeSignal &signal)
{
   if(!InpUseRegimePriors || !signal.valid)
      return signal.valid;

   int regime = CurrentMarketRegime();
   int trend = GetDealingRangeTrend();
   bool mean_reversion_setup = StringFind(signal.setup, "SR_Bounce") >= 0 ||
                               StringFind(signal.setup, "SR_FalseBreakoutTrap") >= 0 ||
                               StringFind(signal.setup, "SR_ChannelBoundary") >= 0 ||
                               StringFind(signal.setup, "RANGE_Cycle") >= 0;
   bool breakout_setup = StringFind(signal.setup, "Breakout") >= 0 ||
                         StringFind(signal.setup, "TrendBreaker") >= 0 ||
                         StringFind(signal.setup, "OuterRange") >= 0 ||
                         StringFind(signal.setup, "Break_CHoCH") >= 0 ||
                         StringFind(signal.setup, "BreakRetest") >= 0 ||
                         StringFind(signal.setup, "BOS_Retest") >= 0 ||
                         StringFind(signal.setup, "OB_SR_") >= 0 ||
                         StringFind(signal.setup, "NFP_") >= 0;

   if(regime == 1 && trend != 0)
   {
      // Trending market: never fade the H1 trend with a mean-reversion setup.
      // This is where SRBounce lost most of its money in the old journal.
      if(mean_reversion_setup && signal.direction == -trend)
      {
         g_last_value_filter_reason = "No trade: counter-trend SR fade blocked in a trending regime";
         return false;
      }
      if(signal.direction == trend &&
         (StringFind(signal.strategy, "TrendFollowing") >= 0 ||
          StringFind(signal.strategy, "FVGRetest") >= 0))
      {
         signal.score = ClampDouble(signal.score + 5.0, 0.0, 100.0);
         signal.reason = AppendToken(signal.reason, "trend-regime alignment");
      }
   }
   else if(regime == 2)
   {
      // Ranging market: range-edge setups lead; raw momentum entries lag.
      if(mean_reversion_setup)
      {
         signal.score = ClampDouble(signal.score + 5.0, 0.0, 100.0);
         signal.reason = AppendToken(signal.reason, "range-regime alignment");
      }
      if(StringFind(signal.setup, "TrendBreaker") >= 0 ||
         StringFind(signal.setup, "MA_TSMOM") >= 0)
         signal.score = ClampDouble(signal.score - 6.0, 0.0, 100.0);
   }
   else if(regime == 3)
   {
      // Volatile expansion: no mean reversion into a moving train.
      if(mean_reversion_setup || StringFind(signal.setup, "TL_H1_SupportTouch") >= 0 ||
         StringFind(signal.setup, "TL_H1_ResistanceTouch") >= 0)
      {
         g_last_value_filter_reason = "No trade: mean-reversion setups are benched during volatile expansion";
         return false;
      }
      if(!breakout_setup && StringFind(signal.setup, "FVG") < 0)
      {
         g_last_value_filter_reason = "No trade: expansion regime accepts only breakout or FVG continuation setups";
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| V6.20 - Self-confirmed setups and add-on position helpers         |
//+------------------------------------------------------------------+
bool IsSelfConfirmedSetup(string setup)
{
   return StringFind(setup, "TL_H1_") >= 0 ||
          StringFind(setup, "BOS_Retest") >= 0 ||
          StringFind(setup, "RANGE_Cycle") >= 0 ||
          StringFind(setup, "ROTATION_") >= 0 ||
          StringFind(setup, "NFP_") >= 0;
}

int EffectiveMaxPositions()
{
   int base = MathMax(1, InpMaxPositionsPerSymbol);
   if(InpUsePilotFirstTrade && PilotStage() == 2)
   {
      int addons = (int)MathMax(0, MathMin(2, InpMaxConfirmationAddOns));
      base = MathMax(base, 1 + addons);
   }
   return base;
}

bool AnyOurPositionInLoss()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetDouble(POSITION_PROFIT) < 0.0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| V6.20 - H1 trendline touch strategy                               |
//+------------------------------------------------------------------+
bool BuildTrendlineTouchSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   if(!InpEnableTrendlineTouch)
      return false;

   // direction 1 buys an ascending support line; -1 sells a descending resistance line.
   TrendLine line;
   if(!BuildThreePointTrendLine(InpTrendlineTF, direction, line))
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, MathMax(40, InpRetestLookbackBars + 10), rates);
   if(copied < 8)
      return false;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;
   double line_now = ProjectTrendLine(line, rates[1].time);
   if(line_now <= 0.0)
      return false;
   double tolerance = atr * MathMax(0.05, InpTrendlineTouchATR);

   // V6.30: the journal showed first-touch trendline entries losing (33-40%
   // win rate). The current touch must now be at least the FOURTH distinct
   // touch of the line - three anchors plus one retest already proved it.
   if(InpRequireSecondRetest)
   {
      int line_touches = CountTrendlineTouches(rates, copied, line.t1, line.p1,
                                               line.t2, line.p2, direction, tolerance);
      if(line_touches < MathMax(3, InpTrendlineMinLineTouches))
         return false;
   }

   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), atr * 0.20);

   if(direction == 1)
   {
      // Buy the touch of the ascending line, but only on a confirmed
      // wick/candle rejection - never on the touch alone.
      bool touched = rates[1].low <= line_now + tolerance && rates[1].close > line_now;
      bool rejected = HasBullishCandlePattern(rates) ||
                      (rates[1].close > rates[1].open && LowerShadow(rates[1]) >= BodySize(rates[1]));
      if(!touched || !rejected)
         return false;
      if(GetDealingRangeTrend() == -1)
         return false;   // never buy a support line inside a bearish H1 regime

      signal.sl = NormalizePrice(MathMin(rates[1].low, line_now) - buffer);
      signal.tp = NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward);
      signal.setup = "TL_H1_SupportTouch";
      signal.reason = TimeframeToText(InpTrendlineTF) +
                      " ascending trendline support touch with bullish wick/candle rejection";
   }
   else
   {
      bool touched = rates[1].high >= line_now - tolerance && rates[1].close < line_now;
      bool rejected = HasBearishCandlePattern(rates) ||
                      (rates[1].close < rates[1].open && UpperShadow(rates[1]) >= BodySize(rates[1]));
      if(!touched || !rejected)
         return false;
      if(GetDealingRangeTrend() == 1)
         return false;   // never sell a resistance line inside a bullish H1 regime

      signal.sl = NormalizePrice(MathMax(rates[1].high, line_now) + buffer);
      signal.tp = NormalizePrice(entry - MathAbs(signal.sl - entry) * InpDefaultRiskReward);
      signal.setup = "TL_H1_ResistanceTouch";
      signal.reason = TimeframeToText(InpTrendlineTF) +
                      " descending trendline resistance touch with bearish wick/candle rejection";
   }

   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "SRBounce";
   signal.score = InpTrendlineScore;

   // Prefer a real historical level as the target; keep the R-multiple
   // target when no clean level exists so a valid touch is not discarded.
   if(!SetEquilibriumContinuationTarget(signal))
      EnsureMinimumRiskReward(direction, entry, signal.sl, signal.tp);
   return true;
}

//+------------------------------------------------------------------+
//| V6.20 - H1 trendline break-and-retest strategy                    |
//+------------------------------------------------------------------+
bool BuildTrendlineBreakRetestSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   if(!InpEnableTrendlineBreakRetest)
      return false;

   // A buy trades the break of a DESCENDING resistance line; a sell trades
   // the break of an ASCENDING support line - then waits for the retest.
   int line_type = (direction == 1) ? -1 : 1;
   TrendLine line;
   if(!BuildThreePointTrendLine(InpTrendlineTF, line_type, line))
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, 60, rates);
   if(copied < 20)
      return false;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;
   double tolerance = atr * MathMax(0.05, InpTrendlineTouchATR);
   int confirm = MathMax(1, InpTrendlineBreakCloses);

   // The break must already be confirmed by consecutive closed bars beyond the line...
   int break_index = -1;
   for(int i = 2; i <= MathMin(copied - confirm - 2, 30); i++)
   {
      bool all_beyond = true;
      for(int k = 0; k < confirm; k++)
      {
         double line_price = ProjectTrendLine(line, rates[i + k].time);
         bool beyond = (direction == 1) ? rates[i + k].close > line_price + tolerance * 0.5
                                        : rates[i + k].close < line_price - tolerance * 0.5;
         if(line_price <= 0.0 || !beyond)
         {
            all_beyond = false;
            break;
         }
      }
      if(all_beyond && BodyRatio(rates[i]) >= 0.50)
      {
         break_index = i;
         break;
      }
   }
   if(break_index < 0)
      return false;

   // ...and the current closed bar must be the retest that HOLDS the line
   // from the other side with a rejection candle.
   double line_now = ProjectTrendLine(line, rates[1].time);
   if(line_now <= 0.0)
      return false;

   bool retest_holds;
   if(direction == 1)
      retest_holds = rates[1].low <= line_now + tolerance && rates[1].close > line_now &&
                     (HasBullishCandlePattern(rates) ||
                      (rates[1].close > rates[1].open && BodyRatio(rates[1]) >= 0.50));
   else
      retest_holds = rates[1].high >= line_now - tolerance && rates[1].close < line_now &&
                     (HasBearishCandlePattern(rates) ||
                      (rates[1].close < rates[1].open && BodyRatio(rates[1]) >= 0.50));
   if(!retest_holds)
      return false;

   // Never trade the break-retest straight into an opposing H1 regime.
   int h1_trend = GetDealingRangeTrend();
   if(h1_trend == -direction && !HasFreshStructureShiftMomentum(direction, InpStructureTF))
      return false;

   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), atr * 0.20);
   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "TrendFollowing";
   signal.setup = (direction == 1) ? "TL_H1_BreakRetest_Buy" : "TL_H1_BreakRetest_Sell";
   signal.reason = TimeframeToText(InpTrendlineTF) +
                   ((direction == 1) ? " descending trendline broken and retested as support"
                                     : " ascending trendline broken and retested as resistance");
   signal.score = InpTrendlineScore + 2.0;
   signal.sl = (direction == 1) ? NormalizePrice(MathMin(rates[1].low, line_now) - buffer)
                                : NormalizePrice(MathMax(rates[1].high, line_now) + buffer);
   signal.tp = (direction == 1) ? NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward)
                                : NormalizePrice(entry - MathAbs(signal.sl - entry) * InpDefaultRiskReward);

   if(!SetEquilibriumContinuationTarget(signal))
      EnsureMinimumRiskReward(direction, entry, signal.sl, signal.tp);
   return true;
}

//+------------------------------------------------------------------+
//| V6.20 - Break-of-structure retest strategy                        |
//+------------------------------------------------------------------+
bool BuildBOSRetestSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   if(!InpEnableBOSRetest)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0,
                          MathMax(80, InpBOSRetestLookback + 30), rates);
   if(copied < 40)
      return false;

   // Find the most recent confirmed structure break in this direction:
   // a CHoCH (structure shift) or a with-trend BOS on the current bar.
   int shift_index = -1;
   double break_level = 0.0;
   bool has_shift = FindRecentStructureShiftLevel(direction, rates, copied, shift_index, break_level) &&
                    shift_index <= MathMax(6, InpBOSRetestLookback);

   if(!has_shift)
   {
      MarketStructure ms = AnalyzeStructure(rates, copied, MathMax(2, InpStructureSwingDepth));
      bool with_trend_bos = (direction == 1) ? (ms.trend == 1 && ms.bullish_bos)
                                             : (ms.trend == -1 && ms.bearish_bos);
      if(!with_trend_bos)
         return false;
      break_level = (direction == 1) ? ms.prev_high : ms.prev_low;
      shift_index = 1;
   }
   if(break_level <= 0.0)
      return false;

   // V6.20 quality gates - this is what the losing role-reversal buy lacked:
   // the break direction must agree with the H1 regime (or be a genuine
   // fresh shift), and price must have LEFT the level before retesting it.
   int h1_trend = GetDealingRangeTrend();
   if(h1_trend == -direction && !HasFreshStructureShiftMomentum(direction, InpStructureTF))
      return false;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;
   double tolerance = MathMax(5.0 * _Point, atr * 0.25);

   bool left_level = shift_index <= 3;   // a very fresh break may retest immediately
   for(int i = 2; i < shift_index && !left_level; i++)
   {
      bool away = (direction == 1) ? rates[i].low > break_level + tolerance
                                   : rates[i].high < break_level - tolerance;
      if(away)
         left_level = true;
   }
   if(!left_level)
      return false;

   // The current closed M15 bar must be the retest holding with a rejection.
   bool retest_holds;
   if(direction == 1)
      retest_holds = rates[1].low <= break_level + tolerance && rates[1].close > break_level &&
                     (HasBullishCandlePattern(rates) ||
                      (rates[1].close > rates[1].open && BodyRatio(rates[1]) >= 0.55));
   else
      retest_holds = rates[1].high >= break_level - tolerance && rates[1].close < break_level &&
                     (HasBearishCandlePattern(rates) ||
                      (rates[1].close < rates[1].open && BodyRatio(rates[1]) >= 0.55));
   if(!retest_holds)
      return false;

   // M5 must confirm the hold as well.
   if(!HasM5LevelRetest(direction, break_level))
      return false;

   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), atr * 0.20);
   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "TrendFollowing";
   signal.setup = (direction == 1) ? "BOS_Retest_Buy" : "BOS_Retest_Sell";
   signal.reason = (direction == 1) ?
                   "confirmed bullish structure break; broken level held as support on the M15 and M5 retest" :
                   "confirmed bearish structure break; broken level held as resistance on the M15 and M5 retest";
   signal.score = InpBOSRetestScore;
   signal.sl = (direction == 1) ? NormalizePrice(MathMin(rates[1].low, break_level) - buffer)
                                : NormalizePrice(MathMax(rates[1].high, break_level) + buffer);
   signal.tp = (direction == 1) ? NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward)
                                : NormalizePrice(entry - MathAbs(signal.sl - entry) * InpDefaultRiskReward);

   if(!SetEquilibriumContinuationTarget(signal))
      EnsureMinimumRiskReward(direction, entry, signal.sl, signal.tp);
   return true;
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| V6.30 - Clustered equal-high / equal-low boundary detection       |
//| Finds levels like "many highs peaked at 6732" by clustering all   |
//| confirmed swing pivots within a tolerance and keeping the level   |
//| with the most touches that is still intact.                       |
//+------------------------------------------------------------------+
bool FindClusterBoundary(const MqlRates &rates[], int copied, int direction,
                         double &level, int &touches, double &cluster_half_width)
{
   level = 0.0;
   touches = 0;
   cluster_half_width = 0.0;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;
   double tol = atr * MathMax(0.05, InpClusterTolATR);
   int depth = MathMax(2, InpStructureSwingDepth);
   int max_i = MathMin(copied - depth - 1, InpSRLookbackBars);

   double pivots[128];
   int pivot_count = 0;
   for(int i = depth + 1; i < max_i && pivot_count < 128; i++)
   {
      bool swing = (direction == -1) ? IsSwingHigh(rates, copied, i, depth)
                                     : IsSwingLow(rates, copied, i, depth);
      if(!swing)
         continue;
      pivots[pivot_count] = (direction == -1) ? rates[i].high : rates[i].low;
      pivot_count++;
   }
   if(pivot_count < MathMax(2, InpClusterMinTouches))
      return false;

   double best_level = 0.0;
   int best_touches = 0;
   double best_width = 0.0;
   double current = rates[1].close;

   for(int a = 0; a < pivot_count; a++)
   {
      double sum = 0.0;
      int n = 0;
      double lo = pivots[a];
      double hi = pivots[a];
      for(int b = 0; b < pivot_count; b++)
      {
         if(MathAbs(pivots[b] - pivots[a]) > tol)
            continue;
         sum += pivots[b];
         n++;
         lo = MathMin(lo, pivots[b]);
         hi = MathMax(hi, pivots[b]);
      }
      if(n == 0)
         continue;
      double mean = sum / n;
      bool better = n > best_touches ||
                    (n == best_touches && MathAbs(mean - current) < MathAbs(best_level - current));
      if(better)
      {
         best_touches = n;
         best_level = mean;
         best_width = (hi - lo) * 0.5;
      }
   }

   if(best_touches < MathMax(2, InpClusterMinTouches))
      return false;
   // The boundary must still be intact - recently closed-through levels are out.
   if(LevelInvalidated(rates, copied, best_level, (direction == -1) ? -1 : 1))
      return false;

   level = NormalizePrice(best_level);
   touches = best_touches;
   cluster_half_width = MathMax(best_width, tol * 0.5);
   return true;
}

//+------------------------------------------------------------------+
//| V6.30 - Range Cycle strategy                                      |
//| Buy the clustered range low, sell the clustered range high, and   |
//| exit at InpRangeExitPercent of the way to the opposite boundary.  |
//+------------------------------------------------------------------+
bool BuildRangeCycleSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   if(!InpEnableRangeCycle)
      return false;
   if(InpRangeCycleOnlyWhenRanging && CurrentMarketRegime() != 2)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, InpSRLookbackBars + 30, rates);
   if(copied < 60)
      return false;

   double res_level = 0.0, sup_level = 0.0;
   int res_touches = 0, sup_touches = 0;
   double res_width = 0.0, sup_width = 0.0;
   if(!FindClusterBoundary(rates, copied, -1, res_level, res_touches, res_width))
      return false;
   if(!FindClusterBoundary(rates, copied, 1, sup_level, sup_touches, sup_width))
      return false;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   double height = res_level - sup_level;
   if(atr <= 0.0 || height < atr * MathMax(0.5, InpRangeMinHeightATR))
      return false;

   double close1 = rates[1].close;
   if(close1 <= sup_level - sup_width || close1 >= res_level + res_width)
      return false;   // price has left the range; the cycle is over

   double exit_pct = ClampDouble(InpRangeExitPercent, 50.0, 100.0);
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), atr * 0.20);

   if(direction == 1)
   {
      bool touched = rates[1].low <= sup_level + sup_width && close1 > sup_level - sup_width;
      bool rejected = HasBullishCandlePattern(rates) ||
                      (rates[1].close > rates[1].open && LowerShadow(rates[1]) >= BodySize(rates[1]));
      if(!touched || !rejected)
         return false;

      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      signal.sl = NormalizePrice(sup_level - sup_width - buffer);
      // Exit BELOW the range high: 90% of the way there by default, so the
      // order fills before the boundary sellers do.
      signal.tp = NormalizePrice(res_level - height * (100.0 - exit_pct) / 100.0);
      if(signal.tp <= entry)
         return false;
      signal.setup = "RANGE_Cycle_Buy";
      signal.reason = "range low held: " + IntegerToString(sup_touches) +
                      " clustered dips at " + DoubleToString(sup_level, _Digits) +
                      ", target " + DoubleToString(exit_pct, 0) + "% of the way to " +
                      IntegerToString(res_touches) + " clustered peaks at " +
                      DoubleToString(res_level, _Digits);
   }
   else
   {
      bool touched = rates[1].high >= res_level - res_width && close1 < res_level + res_width;
      bool rejected = HasBearishCandlePattern(rates) ||
                      (rates[1].close < rates[1].open && UpperShadow(rates[1]) >= BodySize(rates[1]));
      if(!touched || !rejected)
         return false;

      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      signal.sl = NormalizePrice(res_level + res_width + buffer);
      signal.tp = NormalizePrice(sup_level + height * (100.0 - exit_pct) / 100.0);
      if(signal.tp >= entry)
         return false;
      signal.setup = "RANGE_Cycle_Sell";
      signal.reason = "range high held: " + IntegerToString(res_touches) +
                      " clustered peaks at " + DoubleToString(res_level, _Digits) +
                      ", target " + DoubleToString(exit_pct, 0) + "% of the way to " +
                      IntegerToString(sup_touches) + " clustered dips at " +
                      DoubleToString(sup_level, _Digits);
   }

   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "SRBounce";
   signal.score = ClampDouble(InpRangeCycleScore +
                              MathMin(6.0, (res_touches + sup_touches -
                                            2 * MathMax(2, InpClusterMinTouches)) * 1.0),
                              0.0, 100.0);
   return true;
}

//+------------------------------------------------------------------+
//| V6.30 - Draw the clustered range boundaries on the chart          |
//+------------------------------------------------------------------+
void DrawRangeClusterLines(const MqlRates &rates[], int copied)
{
   double res_level = 0.0, sup_level = 0.0;
   int res_touches = 0, sup_touches = 0;
   double res_width = 0.0, sup_width = 0.0;
   bool has_res = FindClusterBoundary(rates, copied, -1, res_level, res_touches, res_width);
   bool has_sup = FindClusterBoundary(rates, copied, 1, sup_level, sup_touches, sup_width);
   datetime end = rates[0].time + (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);

   if(has_res)
   {
      DrawCleanPriceLine("SCE312_VIS_RangeHigh", res_level, C'165,55,135', STYLE_SOLID, 2,
                          "Clustered equal highs - range boundary");
      DrawCleanText("SCE312_VIS_RangeHigh_Label", end, res_level,
                    "Range High (" + IntegerToString(res_touches) + " peaks)", C'165,55,135', 9);
   }
   if(has_sup)
   {
      DrawCleanPriceLine("SCE312_VIS_RangeLow", sup_level, C'20,130,135', STYLE_SOLID, 2,
                          "Clustered equal lows - range boundary");
      DrawCleanText("SCE312_VIS_RangeLow_Label", end, sup_level,
                    "Range Low (" + IntegerToString(sup_touches) + " dips)", C'20,130,135', 9);
   }
}

//+------------------------------------------------------------------+
//| V6.30 - Add-on spacing: pyramids only into profit, never stacked  |
//+------------------------------------------------------------------+
bool AddOnConditionsMet(int direction)
{
   double last_entry = 0.0;
   int last_direction = 0;
   datetime last_time = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      if(open_time >= last_time)
      {
         last_time = open_time;
         last_entry = PositionGetDouble(POSITION_PRICE_OPEN);
         last_direction = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      }
   }
   if(last_direction == 0)
      return true;

   if(direction != last_direction)
   {
      g_last_dashboard_signal = "Add-on skipped: opposite direction while positions are open";
      return false;
   }

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return true;
   double current = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double favorable = (current - last_entry) * direction;
   if(favorable < atr * MathMax(0.0, InpAddOnMinSpacingATR))
   {
      g_last_dashboard_signal = "Add-on skipped: waiting for spacing from the last entry";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| V6.31 - Qualified premium/discount rotation                       |
//| Sell a proven multi-touch boundary rejection in PREMIUM (buy the  |
//| mirror in DISCOUNT), even against the H1 trend, provided:         |
//|  - the boundary has enough touches and is still intact,           |
//|  - the closed M15 candle rejected it with a real wick/pattern,    |
//|  - M15 structure does not oppose the rotation (pausing trend),    |
//| and ride to InpRotationExitPercent of the way to the opposite     |
//| support/resistance. This is the "bearish hammer in the red zone"  |
//| trade, made safe by qualification and a reduced risk budget.      |
//+------------------------------------------------------------------+
bool BuildRotationSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   if(!InpEnableRotationTrades)
      return false;

   DealingRange range;
   if(!GetConfirmedDealingRange(range))
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, InpSRLookbackBars + 30, rates);
   if(copied < 60)
      return false;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;
   double tolerance = GetSRZoneTolerance();
   double close1 = rates[1].close;
   double exit_pct = ClampDouble(InpRotationExitPercent, 50.0, 100.0);
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), atr * 0.20);

   // The trend may be pausing, but M15 structure must not actively run
   // against the rotation (this is what separates a rotation from a fade).
   int m15_trend = GetResponsiveStructureTrend(InpStructureTF);
   if(InpRotationBlockVsM15Trend && m15_trend == -direction)
      return false;

   if(direction == -1)
   {
      // --- SELL a premium rejection -----------------------------------
      if(close1 <= range.equilibrium + range.equilibrium_band)
         return false;   // not in premium: this is not a rotation location

      // The rejected boundary: the confirmed resistance line, or the
      // clustered equal-highs boundary if it is the stronger reference.
      PriceZone resistance = FindSRZone(rates, copied, -1, tolerance);
      double cl_level = 0.0;
      int cl_touches = 0;
      double cl_width = 0.0;
      bool has_cluster = FindClusterBoundary(rates, copied, -1, cl_level, cl_touches, cl_width);

      double zone_low = 0.0, zone_high = 0.0;
      int zone_touches = 0;
      if(resistance.valid && (!has_cluster || resistance.touches >= cl_touches))
      {
         zone_low = resistance.low;
         zone_high = resistance.high;
         zone_touches = resistance.touches;
      }
      else if(has_cluster)
      {
         zone_low = cl_level - cl_width;
         zone_high = cl_level + cl_width;
         zone_touches = cl_touches;
      }
      if(zone_touches < MathMax(2, InpRotationMinTouches) || zone_high <= 0.0)
         return false;

      bool touched = rates[1].high >= zone_low && close1 < zone_high;
      bool rejected = IsBearishPinBar(rates[1]) || IsBearishEngulfing(rates, 1) ||
                      (rates[1].close < rates[1].open && UpperShadow(rates[1]) >= BodySize(rates[1]));
      if(!touched || !rejected)
         return false;

      // Destination: the confirmed support line if one sits below, else the
      // clustered range low, else the dealing-range low itself.
      PriceZone support = FindSRZone(rates, copied, 1, tolerance);
      double sup_cl_level = 0.0;
      int sup_cl_touches = 0;
      double sup_cl_width = 0.0;
      bool has_sup_cluster = FindClusterBoundary(rates, copied, 1, sup_cl_level, sup_cl_touches, sup_cl_width);

      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double target_level = range.low;
      if(support.valid)
      {
         double line = (support.low + support.high) * 0.5;
         if(line < entry - atr * 0.50)
            target_level = MathMax(target_level, line);
      }
      if(has_sup_cluster && sup_cl_level < entry - atr * 0.50)
         target_level = MathMax(MathMin(target_level, sup_cl_level), range.low);
      if(target_level >= entry)
         return false;

      signal.sl = NormalizePrice(MathMax(zone_high, rates[1].high) + buffer);
      signal.tp = NormalizePrice(entry - (entry - target_level) * exit_pct / 100.0);
      if(signal.tp >= entry)
         return false;

      signal.valid = true;
      signal.direction = -1;
      signal.strategy = "SRBounce";
      signal.setup = "ROTATION_PremiumSell";
      signal.score = ClampDouble(InpRotationScore + MathMin(5.0, (zone_touches - InpRotationMinTouches) * 1.5), 0.0, 100.0);
      signal.reason = "premium rejection at a " + IntegerToString(zone_touches) +
                      "-touch boundary with a bearish rejection candle; rotating " +
                      DoubleToString(exit_pct, 0) + "% of the way to support at " +
                      DoubleToString(target_level, _Digits);
      return true;
   }

   // --- BUY a discount rejection (mirror) ------------------------------
   if(close1 >= range.equilibrium - range.equilibrium_band)
      return false;   // not in discount

   PriceZone support2 = FindSRZone(rates, copied, 1, tolerance);
   double scl_level = 0.0;
   int scl_touches = 0;
   double scl_width = 0.0;
   bool has_scl = FindClusterBoundary(rates, copied, 1, scl_level, scl_touches, scl_width);

   double zlow = 0.0, zhigh = 0.0;
   int ztouches = 0;
   if(support2.valid && (!has_scl || support2.touches >= scl_touches))
   {
      zlow = support2.low;
      zhigh = support2.high;
      ztouches = support2.touches;
   }
   else if(has_scl)
   {
      zlow = scl_level - scl_width;
      zhigh = scl_level + scl_width;
      ztouches = scl_touches;
   }
   if(ztouches < MathMax(2, InpRotationMinTouches) || zhigh <= 0.0)
      return false;

   bool touched_low = rates[1].low <= zhigh && close1 > zlow;
   bool rejected_low = IsBullishPinBar(rates[1]) || IsBullishEngulfing(rates, 1) ||
                       (rates[1].close > rates[1].open && LowerShadow(rates[1]) >= BodySize(rates[1]));
   if(!touched_low || !rejected_low)
      return false;

   PriceZone resistance2 = FindSRZone(rates, copied, -1, tolerance);
   double rcl_level = 0.0;
   int rcl_touches = 0;
   double rcl_width = 0.0;
   bool has_rcl = FindClusterBoundary(rates, copied, -1, rcl_level, rcl_touches, rcl_width);

   double entry2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double target_up = range.high;
   if(resistance2.valid)
   {
      double line = (resistance2.low + resistance2.high) * 0.5;
      if(line > entry2 + atr * 0.50)
         target_up = MathMin(target_up, line) > entry2 ? MathMin(target_up, line) : target_up;
   }
   if(has_rcl && rcl_level > entry2 + atr * 0.50)
      target_up = MathMin(MathMax(target_up, rcl_level), range.high);
   if(target_up <= entry2)
      return false;

   signal.sl = NormalizePrice(MathMin(zlow, rates[1].low) - buffer);
   signal.tp = NormalizePrice(entry2 + (target_up - entry2) * exit_pct / 100.0);
   if(signal.tp <= entry2)
      return false;

   signal.valid = true;
   signal.direction = 1;
   signal.strategy = "SRBounce";
   signal.setup = "ROTATION_DiscountBuy";
   signal.score = ClampDouble(InpRotationScore + MathMin(5.0, (ztouches - InpRotationMinTouches) * 1.5), 0.0, 100.0);
   signal.reason = "discount rejection at a " + IntegerToString(ztouches) +
                   "-touch boundary with a bullish rejection candle; rotating " +
                   DoubleToString(exit_pct, 0) + "% of the way to resistance at " +
                   DoubleToString(target_up, _Digits);
   return true;
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| V6.33 - M30 Order Block engine (SMC)                              |
//| Bullish OB: the last downclose candle before an upward            |
//| displacement whose very next candle closes above the OB high.     |
//| Bearish OB is the mirror. A block must be unmitigated (no return  |
//| into it since leaving) so the CURRENT return is the first retest, |
//| which per the SMC model is the entry. Cached per OB-TF bar.       |
//+------------------------------------------------------------------+
bool ScanM30OrderBlock(int direction, PriceZone &ob)
{
   ob = PriceZoneEmpty();
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int need = MathMax(80, InpOBLookbackBars + 20);
   int copied = CopyRates(_Symbol, InpOrderBlockTF, 0, need, rates);
   if(copied < 40)
      return false;

   double atr = GetATR(_Symbol, InpOrderBlockTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;
   double min_impulse = atr * MathMax(0.25, InpOBMinDisplacementATR);
   int limit = MathMin(copied - 8, MathMin(InpOBLookbackBars, MathMax(10, InpOBMaxAgeBars)));

   for(int i = 2; i <= limit; i++)
   {
      if(direction == 1)
      {
         // The last downclose candle before the upswing...
         if(rates[i].close >= rates[i].open)
            continue;
         // ...whose displacement candle closes decisively above it...
         if(rates[i - 1].close <= rates[i].high)
            continue;
         // ...and the impulse away from the block is meaningful.
         double impulse_high = rates[i - 1].high;
         int k_end = MathMax(1, i - 6);
         for(int k = i - 1; k >= k_end; k--)
            impulse_high = MathMax(impulse_high, rates[k].high);
         if(impulse_high - rates[i].low < min_impulse)
            continue;

         // Unmitigated: no return into the block since leaving. The two most
         // recent bars are excluded so the CURRENT return is the entry.
         bool mitigated = false;
         for(int m = i - 2; m >= 3; m--)
            if(rates[m].low <= rates[i].high) { mitigated = true; break; }
         if(mitigated)
            continue;

         ob.valid = true;
         ob.direction = 1;
         ob.low = rates[i].low;
         ob.high = rates[i].high;
         ob.timeframe = InpOrderBlockTF;
         ob.start_time = rates[i].time;
         ob.end_time = rates[1].time;
         ob.strength = ZONE_UNTESTED;
         ob.label = "M30 Bullish OB";
         return true;
      }
      else
      {
         if(rates[i].close <= rates[i].open)
            continue;
         if(rates[i - 1].close >= rates[i].low)
            continue;
         double impulse_low = rates[i - 1].low;
         int k_end2 = MathMax(1, i - 6);
         for(int k = i - 1; k >= k_end2; k--)
            impulse_low = MathMin(impulse_low, rates[k].low);
         if(rates[i].high - impulse_low < min_impulse)
            continue;

         bool mitigated2 = false;
         for(int m = i - 2; m >= 3; m--)
            if(rates[m].high >= rates[i].low) { mitigated2 = true; break; }
         if(mitigated2)
            continue;

         ob.valid = true;
         ob.direction = -1;
         ob.low = rates[i].low;
         ob.high = rates[i].high;
         ob.timeframe = InpOrderBlockTF;
         ob.start_time = rates[i].time;
         ob.end_time = rates[1].time;
         ob.strength = ZONE_UNTESTED;
         ob.label = "M30 Bearish OB";
         return true;
      }
   }
   return false;
}

bool FindM30OrderBlock(int direction, PriceZone &ob)
{
   ob = PriceZoneEmpty();
   if(!InpEnableOBConfluence && !InpShowM30OrderBlocks)
      return false;

   static datetime cached_bar = 0;
   static PriceZone cached_bull;
   static PriceZone cached_bear;
   static bool cached_bull_ok = false;
   static bool cached_bear_ok = false;

   datetime ob_bar = iTime(_Symbol, InpOrderBlockTF, 0);
   if(ob_bar != cached_bar && ob_bar > 0)
   {
      cached_bar = ob_bar;
      cached_bull_ok = ScanM30OrderBlock(1, cached_bull);
      cached_bear_ok = ScanM30OrderBlock(-1, cached_bear);
   }

   if(direction == 1 && cached_bull_ok)
   {
      ob = cached_bull;
      return true;
   }
   if(direction == -1 && cached_bear_ok)
   {
      ob = cached_bear;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| V6.33 - Order block + SR confluence check                         |
//| The block must overlap a proven horizontal reference: the         |
//| confirmed SR line, the clustered range boundary, or a flipped     |
//| role-reversal level.                                              |
//+------------------------------------------------------------------+
bool OrderBlockHasSRConfluence(int direction, const PriceZone &ob, string &note)
{
   note = "";
   if(!ob.valid)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, InpSRLookbackBars + 30, rates);
   if(copied < 60)
      return false;
   double tolerance = GetSRZoneTolerance();

   PriceZone sr = FindSRZone(rates, copied, direction, tolerance);
   if(sr.valid && ZonesOverlapOrNear(ob, sr, tolerance))
   {
      note = "the confirmed " + string(direction == 1 ? "support" : "resistance") +
             " line (" + IntegerToString(sr.touches) + " touches)";
      return true;
   }

   double cl_level = 0.0;
   int cl_touches = 0;
   double cl_width = 0.0;
   if(FindClusterBoundary(rates, copied, direction, cl_level, cl_touches, cl_width))
   {
      PriceZone cl = ZoneFromPrices(direction, cl_level - cl_width, cl_level + cl_width, "Cluster Boundary");
      if(ZonesOverlapOrNear(ob, cl, tolerance))
      {
         note = "the clustered " + string(direction == 1 ? "range low (" : "range high (") +
                IntegerToString(cl_touches) + string(direction == 1 ? " dips)" : " peaks)");
         return true;
      }
   }

   PriceZone role = FindBrokenRetestedZone(rates, copied, direction, tolerance);
   if(role.valid && ZonesOverlapOrNear(ob, role, tolerance))
   {
      note = (direction == 1) ? "a flipped resistance-to-support level"
                              : "a flipped support-to-resistance level";
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| V6.33 - Standalone OB + SR confluence setup                       |
//| Entry on the first return into the block with a rejection on the  |
//| M15 candle or a confirmation candle on the M2-M5 entry TF. Stop   |
//| beyond the OB candle (the SMC "lowest downclose candle" rule).    |
//+------------------------------------------------------------------+
bool BuildOBConfluenceSignal(int direction, TradeSignal &signal)
{
   EmptySignal(signal);
   if(!InpEnableOBConfluence)
      return false;

   PriceZone ob;
   if(!FindM30OrderBlock(direction, ob))
      return false;

   string confluence = "";
   if(!OrderBlockHasSRConfluence(direction, ob, confluence))
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpStructureTF, 0, 30, rates);
   if(copied < 8)
      return false;

   // Never straight against an opposing H1 regime without a fresh shift.
   int h1_trend = GetDealingRangeTrend();
   if(h1_trend == -direction && !HasFreshStructureShiftMomentum(direction, InpStructureTF))
      return false;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return false;
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), atr * 0.20);
   double ob_mid = (ob.low + ob.high) * 0.5;
   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(direction == 1)
   {
      bool touched = rates[1].low <= ob.high && rates[1].close > ob.low;
      bool rejected = HasBullishCandlePattern(rates) ||
                      (rates[1].close > rates[1].open && LowerShadow(rates[1]) >= BodySize(rates[1])) ||
                      (rates[1].close > ob_mid && HasBullishCandlePatternOnTF(InpEntryTF));
      if(!touched || !rejected)
         return false;

      signal.sl = NormalizePrice(ob.low - buffer);
      signal.tp = NormalizePrice(entry + MathAbs(entry - signal.sl) * InpDefaultRiskReward);
      signal.setup = "OB_SR_Confluence_Buy";
      signal.reason = "fresh M30 bullish order block overlapping " + confluence +
                      "; first return held with a bullish rejection";
   }
   else
   {
      bool touched = rates[1].high >= ob.low && rates[1].close < ob.high;
      bool rejected = HasBearishCandlePattern(rates) ||
                      (rates[1].close < rates[1].open && UpperShadow(rates[1]) >= BodySize(rates[1])) ||
                      (rates[1].close < ob_mid && HasBearishCandlePatternOnTF(InpEntryTF));
      if(!touched || !rejected)
         return false;

      signal.sl = NormalizePrice(ob.high + buffer);
      signal.tp = NormalizePrice(entry - MathAbs(signal.sl - entry) * InpDefaultRiskReward);
      signal.setup = "OB_SR_Confluence_Sell";
      signal.reason = "fresh M30 bearish order block overlapping " + confluence +
                      "; first return held with a bearish rejection";
   }

   signal.valid = true;
   signal.direction = direction;
   signal.strategy = "FVGRetest";
   signal.score = InpOBConfluenceScore;

   if(!SetEquilibriumContinuationTarget(signal))
      EnsureMinimumRiskReward(direction, entry, signal.sl, signal.tp);
   return true;
}

//+------------------------------------------------------------------+
//| V6.33 - Confluence bonus: integrate the OB with every strategy    |
//+------------------------------------------------------------------+
void ApplyOrderBlockConfluence(TradeSignal &signal)
{
   if(!signal.valid || !InpEnableOBConfluence || InpOBConfluenceBonus <= 0.0)
      return;
   if(StringFind(signal.setup, "OB_SR_") >= 0)
      return;   // the standalone OB setup already carries its own weight

   PriceZone ob;
   if(!FindM30OrderBlock(signal.direction, ob))
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpStructureTF, 0, 6, rates) < 3)
      return;

   bool at_block = rates[1].low <= ob.high && rates[1].high >= ob.low;
   if(!at_block)
      return;

   signal.score = ClampDouble(signal.score + MathMax(0.0, InpOBConfluenceBonus), 0.0, 100.0);
   signal.reason = AppendToken(signal.reason, "M30 order block confluence");
}

//+------------------------------------------------------------------+
//| V6.33 - Draw the active M30 order blocks                          |
//+------------------------------------------------------------------+
void DrawM30OrderBlocks()
{
   datetime end = iTime(_Symbol, InpStructureTF, 0) +
                  (datetime)(PeriodSeconds(InpStructureTF) * InpVisualExtendBars);

   PriceZone bull;
   if(FindM30OrderBlock(1, bull))
   {
      string note = "";
      bool confluent = OrderBlockHasSRConfluence(1, bull, note);
      DrawCleanZoneRectangle("SCE312_VIS_M30OB_Bull", bull.start_time, bull.high, end, bull.low,
                             C'198,236,205', confluent ? "M30 Bullish OB @ SR" : "M30 Bullish OB", true);
   }

   PriceZone bear;
   if(FindM30OrderBlock(-1, bear))
   {
      string note2 = "";
      bool confluent2 = OrderBlockHasSRConfluence(-1, bear, note2);
      DrawCleanZoneRectangle("SCE312_VIS_M30OB_Bear", bear.start_time, bear.high, end, bear.low,
                             C'250,205,190', confluent2 ? "M30 Bearish OB @ SR" : "M30 Bearish OB", true);
   }
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| V6.34 - Resting limit orders at confluent order blocks            |
//| One order per direction. The order lives while its block is       |
//| valid, is replaced when a fresher block forms, and is cancelled   |
//| when the block is mitigated, loses its SR confluence, the H1      |
//| regime turns against it, or the position book is full.            |
//+------------------------------------------------------------------+
string OBOrderTicketKey(int direction)
{
   return "SCE312_OBORD_" + _Symbol + "_" + (string)InpMagicNumber + "_" +
          string(direction == 1 ? "B" : "S");
}

string OBOrderTimeKey(int direction)
{
   return "SCE312_OBOTM_" + _Symbol + "_" + (string)InpMagicNumber + "_" +
          string(direction == 1 ? "B" : "S");
}

void ManageOrderBlockLimitOrders()
{
   if(!InpEnableOBConfluence || !InpUseOBLimitOrders)
   {
      // V6.36: when the feature is off, any tracked resting orders are
      // cleaned up so no stale pending can fill behind your back.
      for(int direction = 1; direction >= -1; direction -= 2)
      {
         string tkey = OBOrderTicketKey(direction);
         if(!GlobalVariableCheck(tkey))
            continue;
         ulong stale = (ulong)GlobalVariableGet(tkey);
         if(stale > 0 && OrderSelect(stale))
            trade.OrderDelete(stale);
         GlobalVariableDel(tkey);
         GlobalVariableDel(OBOrderTimeKey(direction));
      }
      return;
   }

   // Once per M15 bar is enough: blocks are M30 objects and the SR
   // confluence scan is not free.
   static datetime last_sync_bar = 0;
   datetime bar = iTime(_Symbol, InpStructureTF, 0);
   if(bar == last_sync_bar || bar <= 0)
      return;
   last_sync_bar = bar;

   SyncOrderBlockLimit(1);
   SyncOrderBlockLimit(-1);
}

void SyncOrderBlockLimit(int direction)
{
   string ticket_key = OBOrderTicketKey(direction);
   string time_key = OBOrderTimeKey(direction);
   ulong existing = GlobalVariableCheck(ticket_key) ? (ulong)GlobalVariableGet(ticket_key) : 0;
   datetime stored_block_time = GlobalVariableCheck(time_key) ? (datetime)(long)GlobalVariableGet(time_key) : 0;

   // A stored ticket that no longer exists (filled, expired, or removed by
   // hand) is forgotten so a fresh block can be armed again.
   if(existing > 0 && !OrderSelect(existing))
   {
      GlobalVariableDel(ticket_key);
      GlobalVariableDel(time_key);
      existing = 0;
      stored_block_time = 0;
   }

   PriceZone ob;
   string confluence = "";
   bool valid = FindM30OrderBlock(direction, ob) &&
                OrderBlockHasSRConfluence(direction, ob, confluence);
   if(valid)
   {
      int h1_trend = GetDealingRangeTrend();
      if(h1_trend == -direction && !HasFreshStructureShiftMomentum(direction, InpStructureTF))
         valid = false;
   }
   if(valid && CountOurPositions(_Symbol) >= EffectiveMaxPositions())
      valid = false;   // the book is full; queue no additional exposure

   if(!valid)
   {
      if(existing > 0)
      {
         trade.OrderDelete(existing);
         GlobalVariableDel(ticket_key);
         GlobalVariableDel(time_key);
      }
      return;
   }

   // The live order already covers this exact block: nothing to change.
   if(existing > 0 && stored_block_time == ob.start_time)
      return;
   if(existing > 0)
   {
      trade.OrderDelete(existing);
      GlobalVariableDel(ticket_key);
      GlobalVariableDel(time_key);
   }

   double depth = ClampDouble(InpOBLimitEntryLevel, 0.0, 100.0) / 100.0;
   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return;
   double buffer = MathMax(GetInitialStopBuffer(InpEntryTF), atr * 0.20);

   double entry, sl;
   if(direction == 1)
   {
      entry = NormalizePrice(ob.high - (ob.high - ob.low) * depth);
      sl = NormalizePrice(ob.low - buffer);
      double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(entry >= current_ask - 2.0 * _Point)
         return;   // price is already at/inside the block; the market path handles it
   }
   else
   {
      entry = NormalizePrice(ob.low + (ob.high - ob.low) * depth);
      sl = NormalizePrice(ob.high + buffer);
      double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(entry <= current_bid + 2.0 * _Point)
         return;
   }

   ApplyMinimumStopDistance(direction, entry, sl);

   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return;
   double max_stop = GetMaximumStopDistance(entry);
   if(max_stop > 0.0 && risk > max_stop)
      return;   // V6.36: resting limits honor the same stop cap as market entries

   // Full target from the LIMIT entry: start at the default R multiple and
   // snap to a real historical M15 level, exactly like a market entry.
   double tp = (direction == 1) ? NormalizePrice(entry + risk * InpDefaultRiskReward)
                                : NormalizePrice(entry - risk * InpDefaultRiskReward);
   ApplyHistoricalM15Target(direction, entry, sl, tp);
   EnsureMinimumRiskReward(direction, entry, sl, tp);

   double volume = CalculateVolumeForRisk((direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, entry, sl);
   if(volume <= 0.0)
   {
      LogJournal("PENDING_REJECTED", 0, _Symbol, DirectionToText(direction), 0.0, entry, 0.0, sl, tp,
                 "FVGRetest", "NO_TRADE", 0.0, "Volume calculation failed for the order-block limit",
                 "Block overlaps " + confluence,
                 g_last_risk_reject_reason == "" ? "Check risk settings" : g_last_risk_reject_reason,
                 (direction == 1) ? "OB_SR_Limit_Buy" : "OB_SR_Limit_Sell");
      return;
   }

   datetime expiry = 0;
   ENUM_ORDER_TYPE_TIME time_type = ORDER_TIME_GTC;
   if(InpOBLimitExpiryBars > 0)
   {
      expiry = TimeCurrent() + (datetime)((long)InpOBLimitExpiryBars * PeriodSeconds(InpOrderBlockTF));
      time_type = ORDER_TIME_SPECIFIED;
   }

   string comment = BuildTradeComment("FVGRetest");
   bool placed = (direction == 1)
                 ? trade.BuyLimit(volume, entry, _Symbol, sl, tp, time_type, expiry, comment)
                 : trade.SellLimit(volume, entry, _Symbol, sl, tp, time_type, expiry, comment);
   if(!placed)
   {
      Print("Order-block limit placement failed. Retcode ",
            (int)trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return;
   }

   ulong new_ticket = trade.ResultOrder();
   GlobalVariableSet(ticket_key, (double)(long)new_ticket);
   GlobalVariableSet(time_key, (double)(long)ob.start_time);
   if(g_last_pilot_lot_used)
      SetPilotStage(1);

   LogJournal("PENDING_SET", new_ticket, _Symbol, DirectionToText(direction), volume, entry, 0.0, sl, tp,
              "FVGRetest", "PENDING", 0.0,
              "Limit order resting at the M30 order block (" +
              DoubleToString(ClampDouble(InpOBLimitEntryLevel, 0.0, 100.0), 0) + "% depth)",
              "Block overlaps " + confluence,
              g_last_pilot_lot_used ? "Pilot minimum-lot pending; full sizing unlocks after confirmation"
                                    : "The order is replaced or cancelled as the block evolves",
              (direction == 1) ? "OB_SR_Limit_Buy" : "OB_SR_Limit_Sell");
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| V6.35 - Breathing-room stop floor                                 |
//| A structural stop is only trusted when it also clears the ATR     |
//| floor. On the (1s) indices especially, a stop hugging the level   |
//| gets clipped by ordinary wick noise before the idea can play out. |
//| The stop is only ever WIDENED to the floor, never tightened, and  |
//| the risk-based sizing automatically shrinks the lot to match.     |
//+------------------------------------------------------------------+
void ApplyMinimumStopDistance(int direction, double entry, double &sl)
{
   if(InpMinStopDistanceATR <= 0.0 || direction == 0 || sl <= 0.0)
      return;

   double atr = GetATR(_Symbol, InpStructureTF, InpTrendATRPeriod, 1);
   if(atr <= 0.0)
      return;

   double floor_distance = atr * InpMinStopDistanceATR;
   double distance = MathAbs(entry - sl);
   if(distance >= floor_distance)
      return;

   sl = NormalizePrice(entry - direction * floor_distance);
}

//+------------------------------------------------------------------+