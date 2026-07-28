//+------------------------------------------------------------------+
//| Test_RiskManager.mq5                                              |
//| Themba Adaptive Intraday Engine — TASK-007 compile/logic test      |
//|                                                                    |
//| Tests 1-10 use a hand-fabricated CSymbolProfile with round-number   |
//| values so every expected result can be verified by hand (test 1 is |
//| the exact worked example from TASK-002_PHASE2_SPECIFICATION.md's   |
//| Test plan item 5: "price move 1.00, tick size 0.01, tick value 1,  |
//| one lot -> risk_cash = 100"). Tests 11-12 use a real symbol via     |
//| OrderCalcProfit, which needs live broker context and cannot be      |
//| hand-fabricated.                                                     |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Risk/RiskManager.mqh"

input string InpTestSymbol = "EURUSD";

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition)
     {
      PrintFormat("PASS: %s", label);
      g_pass++;
     }
   else
     {
      PrintFormat("FAIL: %s", label);
      g_fail++;
     }
  }

bool NearlyEqual(const double a, const double b, const double tol = 0.0001)
  {
   return MathAbs(a - b) <= tol;
  }

void OnStart()
  {
   Print("=== TASK-007 RiskManager test start ===");

   //--- Hand-fabricated profile: tick_size 0.01, tick_value_loss 1.0, --
   //--- volume_min 0.1, matching TASK-002's own worked example. --------
   CSymbolProfile p;
   p.loaded = true;
   p.tick_value = 1.0;
   p.tick_value_profit = 1.0;
   p.tick_value_loss = 1.0;
   p.tick_size = 0.01;
   p.contract_size = 100000.0;
   p.volume_min = 0.1;
   p.volume_max = 100.0;
   p.volume_step = 0.01;
   p.point = 0.00001;

   //--- 1. Exact worked example from TASK-002's Test plan item 5 ------
   double loss_distance = RM_ComputeLossDistance(true, 100.00, 99.00); // 1.00 move
   Check("loss_distance for a 1.00 long move equals 1.00",
         NearlyEqual(loss_distance, 1.00));

   double risk_cash;
   bool rc_ok = RM_ComputeRiskCash(p, loss_distance, 1.0, risk_cash);
   Check("RM_ComputeRiskCash succeeds for the worked example", rc_ok);
   Check("worked example: risk_cash == 100 (matches spec's hand-derivation)",
         NearlyEqual(risk_cash, 100.0));

   //--- 2. A stop on the PROFIT side of entry prices as zero risk -----
   double long_profit_side = RM_ComputeLossDistance(true, 100.00, 101.00);
   Check("long profit-side stop has zero loss_distance",
         NearlyEqual(long_profit_side, 0.0));

   double short_profit_side = RM_ComputeLossDistance(false, 100.00, 99.00);
   Check("short profit-side stop has zero loss_distance",
         NearlyEqual(short_profit_side, 0.0));

   double zero_risk_cash;
   RM_ComputeRiskCash(p, long_profit_side, 1.0, zero_risk_cash);
   Check("profit-side stop produces zero risk_cash",
         NearlyEqual(zero_risk_cash, 0.0));

   //--- 3. A short's loss-side distance is measured correctly ---------
   double short_loss_side = RM_ComputeLossDistance(false, 100.00, 100.50);
   Check("short loss-side (SL above entry) loss_distance == 0.50",
         NearlyEqual(short_loss_side, 0.50));

   //--- 4. Risk percent -------------------------------------------------
   double risk_pct;
   bool pct_ok = RM_ComputeRiskPercent(50.0, 10000.0, risk_pct);
   Check("RM_ComputeRiskPercent succeeds for positive equity", pct_ok);
   Check("50 cash risk on 10000 equity == 0.5%", NearlyEqual(risk_pct, 0.5));

   double bad_pct;
   Check("RM_ComputeRiskPercent fails for zero equity",
         RM_ComputeRiskPercent(50.0, 0.0, bad_pct) == false);

   //--- 5. No-SL fallback ------------------------------------------------
   double no_stop_cash;
   bool ns_ok = RM_ComputeNoStopRiskCash(p, 1.0, 1.0, no_stop_cash, 10.0);
   Check("RM_ComputeNoStopRiskCash succeeds", ns_ok);
   // proxy_loss_distance = 1.0*10 = 10.0; risk_cash = 10*1*1/0.01 = 1000
   Check("no-SL fallback: ATR 1.0 x10 multiple == 1000 risk_cash",
         NearlyEqual(no_stop_cash, 1000.0));

   //--- 6. Stop-floor / cap equations -----------------------------------
   Check("min stop distance: ATR 10 x0.5 == 5",
         NearlyEqual(RM_ComputeMinStopDistance(10.0, 0.5), 5.0));
   // by_price = 2000*0.03 = 60; by_atr = 10*4 = 40; min(60,40) = 40
   Check("max stop distance: min(price-based 60, ATR-based 40) == 40",
         NearlyEqual(RM_ComputeMaxStopDistance(2000.0, 10.0, 3.0, 4.0), 40.0));

   //--- 7. RM_ValidateStopDistance: three branches ---------------------
   double adjusted;
   string reason;
   bool v1 = RM_ValidateStopDistance(2.0, 5.0, 40.0, adjusted, reason);
   Check("stop below floor is widened (returns true)", v1);
   Check("stop below floor: adjusted == floor (5.0)", NearlyEqual(adjusted, 5.0));
   Check("stop below floor: reason == widened_to_floor", reason == "widened_to_floor");

   bool v2 = RM_ValidateStopDistance(50.0, 5.0, 40.0, adjusted, reason);
   Check("stop above cap is REJECTED (returns false, not clamped)", v2 == false);
   Check("stop above cap: reason == stop_exceeds_cap", reason == "stop_exceeds_cap");

   bool v3 = RM_ValidateStopDistance(20.0, 5.0, 40.0, adjusted, reason);
   Check("stop within bounds passes through unchanged", v3);
   Check("stop within bounds: adjusted == original (20.0)", NearlyEqual(adjusted, 20.0));
   Check("stop within bounds: reason is empty (no adjustment)", reason == "");

   //--- 8. Broker-minimum-volume-exceeds-cap rule -----------------------
   double implied_pct;
   // risk_cash at volume_min(0.1) for loss_distance 1.00 = 1.00*0.1*1/0.01 = 10
   bool exceeds_low_equity = RM_BrokerMinVolumeExceedsCap(p, 1.00, 500.0, 1.0, implied_pct);
   // implied = 100*10/500 = 2.0% > 1.0% cap -> exceeds
   Check("min-volume risk exceeds a 1% cap on a 500-equity account",
         exceeds_low_equity);
   Check("implied risk percent for the exceeding case == 2.0%",
         NearlyEqual(implied_pct, 2.0));

   bool exceeds_high_equity = RM_BrokerMinVolumeExceedsCap(p, 1.00, 100000.0, 1.0, implied_pct);
   Check("min-volume risk does NOT exceed a 1% cap on a 100000-equity account",
         exceeds_high_equity == false);

   //--- 9. Real-symbol OrderCalcProfit cross-check ----------------------
   CSymbolProfile real;
   bool real_loaded = real.Load(InpTestSymbol);
   if(real_loaded)
     {
      double price = SymbolInfoDouble(InpTestSymbol, SYMBOL_BID);
      double sl_dist = 50.0 * real.point; // a modest, nonzero distance
      double entry = price;
      double sl = entry - sl_dist;
      double real_loss_distance = RM_ComputeLossDistance(true, entry, sl);

      double real_risk_cash;
      bool real_rc_ok = RM_ComputeRiskCash(real, real_loss_distance, real.volume_min,
                                            real_risk_cash);
      Check(StringFormat("real-symbol '%s' risk_cash computes successfully",
                          InpTestSymbol), real_rc_ok);

      if(real_rc_ok)
        {
         double broker_risk_cash;
         bool cross_ok = RM_CrossCheckRiskCash(InpTestSymbol, true, real.volume_min,
                                                entry, sl, real_risk_cash,
                                                broker_risk_cash, 5.0);
         PrintFormat("INFO: computed risk_cash=%.4f broker risk_cash=%.4f",
                     real_risk_cash, broker_risk_cash);
         Check("OrderCalcProfit cross-check agrees within 5%% tolerance",
               cross_ok);
        }
     }
   else
     {
      PrintFormat("NOTE: '%s' did not load — real-symbol cross-check skipped.",
                  InpTestSymbol);
     }

   PrintFormat("=== TASK-007 RiskManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
