//+------------------------------------------------------------------+
//| RiskManager.mqh                                                   |
//| Themba Adaptive Intraday Engine — Risk                             |
//|                                                                    |
//| The core, stateless risk-math functions from                      |
//| TASK-002_PHASE2_SPECIFICATION.md section 8: per-position risk-cash |
//| (corrected for the round-3-found dimensional error — missing        |
//| division by tick size — and the unsigned-distance error — a stop   |
//| on the profit side of entry must price as zero risk, not a         |
//| negative-then-absolute-valued one), the no-SL worst-case fallback,  |
//| the stop-floor/cap preflight equations, the broker-minimum-volume-  |
//| vs-cap rejection rule, and the `OrderCalcProfit` cross-check        |
//| RISK_POLICY.md and section 8 both require.                          |
//|                                                                    |
//| Deliberately stateless and scoped to pure computation only — this   |
//| is TASK-007. `DailyWeeklyLimits`, `EquityPeakManager`, and          |
//| `DrawdownController` (which need StateManager-backed persisted      |
//| state and live-position enumeration) are a separate, later task,    |
//| per master-prompt section 22's "clear responsibility" rule and      |
//| CLAUDE.md's "implement one bounded task" workflow.                  |
//+------------------------------------------------------------------+
#property strict

#include "../Market/SymbolProfile.mqh"

//+------------------------------------------------------------------+
//| Loss-side distance from entry to stop, per section 8: zero if the  |
//| stop sits on the PROFIT side of entry (e.g. a locked-in profit      |
//| stop), never a signed/unsigned-then-absolute value — this is the    |
//| round-3-corrected formula (the prior draft used an unsigned          |
//| |entry-SL|, which wrongly assigned positive risk to a profit-side    |
//| stop).                                                               |
//+------------------------------------------------------------------+
double RM_ComputeLossDistance(const bool is_long, const double entry_price,
                               const double sl_price)
  {
   if(is_long)
      return MathMax(0.0, entry_price - sl_price);
   return MathMax(0.0, sl_price - entry_price);
  }

//+------------------------------------------------------------------+
//| risk_cash = loss_distance * volume * tick_value_loss / tick_size,  |
//| per section 8's corrected formula (adds the division by tick size   |
//| the round-3 review found missing, and uses the LOSS-side tick       |
//| value specifically, per round-3 finding 8, not the generic one).    |
//| Returns false (risk_cash left at 0.0) if the profile is not loaded  |
//| or tick_size is non-positive — a caller must never trade on a       |
//| false return.                                                       |
//+------------------------------------------------------------------+
bool RM_ComputeRiskCash(const CSymbolProfile &profile, const double loss_distance,
                         const double volume, double &risk_cash)
  {
   risk_cash = 0.0;
   if(!profile.loaded || profile.tick_size <= 0.0)
      return false;
   if(loss_distance < 0.0 || volume < 0.0)
      return false;

   risk_cash = loss_distance * volume * profile.tick_value_loss / profile.tick_size;
   return true;
  }

//+------------------------------------------------------------------+
//| per_trade_risk_pct / total_open_risk_pct — the same formula for     |
//| either, per section 8 ("both now explicitly connected to the        |
//| 1%/1% caps"): 100 * risk_cash / equity. Returns false if equity is  |
//| non-positive (undefined percentage, never silently 0 or infinite).  |
//+------------------------------------------------------------------+
bool RM_ComputeRiskPercent(const double risk_cash, const double equity,
                            double &risk_percent)
  {
   risk_percent = 0.0;
   if(equity <= 0.0)
      return false;
   risk_percent = 100.0 * risk_cash / equity;
   return true;
  }

//+------------------------------------------------------------------+
//| No-SL worst-case risk-cash fallback, per section 8: ATR-multiple    |
//| loss-distance proxy substituted into the SAME formula shape as the  |
//| normal case — not a conflated notional figure (the defect round-3   |
//| found in an earlier draft).                                          |
//+------------------------------------------------------------------+
bool RM_ComputeNoStopRiskCash(const CSymbolProfile &profile, const double atr,
                               const double volume, double &risk_cash,
                               const double atr_multiple = 10.0)
  {
   risk_cash = 0.0;
   if(atr <= 0.0)
      return false;
   double proxy_loss_distance = atr * atr_multiple;
   return RM_ComputeRiskCash(profile, proxy_loss_distance, volume, risk_cash);
  }

//+------------------------------------------------------------------+
//| Stop-floor: min_stop_distance = ATR * multiple, per section 8       |
//| (default multiple 0.5). A tighter pattern/structure-implied stop    |
//| is widened out to this floor by the caller (via                     |
//| RM_ValidateStopDistance below), never traded tighter than this.     |
//+------------------------------------------------------------------+
double RM_ComputeMinStopDistance(const double atr, const double atr_multiple = 0.5)
  {
   return atr * atr_multiple;
  }

//+------------------------------------------------------------------+
//| Stop-cap: max_stop_distance = min(price * max_price_percent/100,    |
//| ATR * max_atr_multiple), per section 8 (defaults 3.0% / 4.0x). A     |
//| structure-implied stop wider than this REJECTS the trade (see        |
//| RM_ValidateStopDistance) rather than being silently clamped.         |
//+------------------------------------------------------------------+
double RM_ComputeMaxStopDistance(const double price, const double atr,
                                  const double max_price_percent = 3.0,
                                  const double max_atr_multiple = 4.0)
  {
   double by_price = price * max_price_percent / 100.0;
   double by_atr    = atr * max_atr_multiple;
   return MathMin(by_price, by_atr);
  }

//+------------------------------------------------------------------+
//| Applies the floor/cap preflight to a candidate stop distance, per   |
//| section 8:                                                          |
//|   - below the floor  -> widened to the floor (adjusted, true)       |
//|   - above the cap    -> REJECTED (adjusted unchanged, false) —      |
//|     never silently clamped, since that would silently change the    |
//|     strategy's own computed risk-reward.                            |
//|   - in between        -> passed through unchanged (adjusted, true)  |
//| 'reason' is always set to a machine-readable string, per             |
//| PROJECT_RULES.md rule 6, even on the pass-through case (empty        |
//| string there, by convention, meaning "no adjustment was needed").    |
//+------------------------------------------------------------------+
bool RM_ValidateStopDistance(const double stop_distance, const double min_stop_distance,
                              const double max_stop_distance, double &adjusted_stop_distance,
                              string &reason)
  {
   adjusted_stop_distance = stop_distance;
   reason = "";

   if(stop_distance > max_stop_distance)
     {
      reason = "stop_exceeds_cap";
      return false;
     }

   if(stop_distance < min_stop_distance)
     {
      adjusted_stop_distance = min_stop_distance;
      reason = "widened_to_floor";
      return true;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| True iff trading the broker's minimum volume would itself exceed    |
//| risk_cap_percent — per RISK_POLICY.md ("Reject broker minimum       |
//| volume when actual risk exceeds the cap") and section 8's blanket    |
//| rule: the trade must be REJECTED outright in that case, never        |
//| rounded up to fit the cap. 'implied_risk_percent' is always set      |
//| (0.0 if it could not be computed) so a caller can log the actual     |
//| figure regardless of the boolean outcome.                            |
//+------------------------------------------------------------------+
bool RM_BrokerMinVolumeExceedsCap(const CSymbolProfile &profile, const double loss_distance,
                                   const double equity, const double risk_cap_percent,
                                   double &implied_risk_percent)
  {
   implied_risk_percent = 0.0;

   double risk_cash;
   if(!RM_ComputeRiskCash(profile, loss_distance, profile.volume_min, risk_cash))
      return false; // undefined — caller's own earlier validation should
                     // already have rejected an unloaded/invalid profile

   if(!RM_ComputeRiskPercent(risk_cash, equity, implied_risk_percent))
      return false;

   return implied_risk_percent > risk_cap_percent;
  }

//+------------------------------------------------------------------+
//| Cross-checks a computed risk_cash against the broker's own          |
//| OrderCalcProfit result for the same parameters, per RISK_POLICY.md   |
//| ("Use OrderCalcProfit to cross-check risk") and section 8's          |
//| blanket rule. Returns false if OrderCalcProfit itself fails, or if   |
//| the two figures disagree by more than tolerance_percent —            |
//| 'broker_risk_cash' is always set when OrderCalcProfit succeeds, so   |
//| a caller can log the actual discrepancy regardless of outcome.       |
//+------------------------------------------------------------------+
bool RM_CrossCheckRiskCash(const string symbol, const bool is_long, const double volume,
                            const double entry_price, const double sl_price,
                            const double computed_risk_cash, double &broker_risk_cash,
                            const double tolerance_percent = 5.0)
  {
   broker_risk_cash = 0.0;
   ENUM_ORDER_TYPE order_type = is_long ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double profit = 0.0;
   if(!OrderCalcProfit(order_type, symbol, volume, entry_price, sl_price, profit))
      return false;

   // A losing trade (which a stop-loss close always is, by definition)
   // reports as a negative profit from OrderCalcProfit — risk_cash is
   // the positive magnitude of that loss.
   broker_risk_cash = -profit;

   if(computed_risk_cash <= 0.0)
      return MathAbs(broker_risk_cash) < 0.01; // both effectively zero

   double diff_percent = 100.0 * MathAbs(broker_risk_cash - computed_risk_cash) /
                          computed_risk_cash;
   return diff_percent <= tolerance_percent;
  }
