//+------------------------------------------------------------------+
//| Test_RegimeGateComposer.mq5                                       |
//| Themba Adaptive Intraday Engine — TASK-034 compile/logic test       |
//|                                                                    |
//| Pure, deterministic, no live trading action — exercises              |
//| RGC_ComposeGates directly against hand-fabricated hysteresis states     |
//| and gate booleans. Confirms each of spread/liquidity, hysteresis, and     |
//| news blackout independently affects the effective regime, that they        |
//| compose correctly (no short-circuit skipping — every gate's own boolean       |
//| is preserved in the result even when another gate determines the               |
//| effective regime), and that spread/liquidity takes priority over news           |
//| when both are simultaneously active (documented file-header policy).             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Market/RegimeGateComposer.mqh"

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

void OnStart()
  {
   Print("=== TASK-034 RegimeGateComposer test start ===");

   //--- 1. No gates active: effective regime tracks hysteresis normally ---
   SRegimeHysteresisState state1;
   MRE_InitHysteresisState(state1);
   SRegimeGateResult r1a = RGC_ComposeGates(state1, REGIME_TRENDING_UP, false, false, "", 2);
   Check("no gates, 1st read: unconfirmed -> TRANSITION_OR_UNCERTAIN",
         r1a.effective_regime == REGIME_TRANSITION_OR_UNCERTAIN);
   Check("no gates, 1st read: neither gate flag set",
         !r1a.spread_liquidity_gate_active && !r1a.news_gate_active);
   SRegimeGateResult r1b = RGC_ComposeGates(state1, REGIME_TRENDING_UP, false, false, "", 2);
   Check("no gates, 2nd consecutive matching read: confirms TRENDING_UP",
         r1b.effective_regime == REGIME_TRENDING_UP);

   //--- 2. Spread/liquidity gate alone overrides immediately (bypass) -----
   SRegimeHysteresisState state2;
   MRE_InitHysteresisState(state2);
   SRegimeGateResult r2 = RGC_ComposeGates(state2, REGIME_TRENDING_UP, true, false, "", 2);
   Check("spread/liquidity gate alone -> effective regime is UNTRADEABLE, "
         "bypassing hysteresis on the very first read",
         r2.effective_regime == REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY);
   Check("spread/liquidity gate flag reported active", r2.spread_liquidity_gate_active);
   Check("news gate flag NOT reported active", !r2.news_gate_active);

   //--- 3. News gate alone overrides immediately (bypass) ------------------
   SRegimeHysteresisState state3;
   MRE_InitHysteresisState(state3);
   SRegimeGateResult r3 = RGC_ComposeGates(state3, REGIME_RANGING, false, true, "EVT123", 2);
   Check("news gate alone -> effective regime is NEWS_BLACKOUT, bypassing "
         "hysteresis on the very first read",
         r3.effective_regime == REGIME_NEWS_BLACKOUT);
   Check("news gate flag reported active", r3.news_gate_active);
   Check("news triggering_event_id is passed through", r3.news_triggering_event_id == "EVT123");
   Check("spread/liquidity gate flag NOT reported active", !r3.spread_liquidity_gate_active);

   //--- 4. Both gates simultaneously active: spread/liquidity wins as the -
   //--- effective regime, but BOTH flags remain reported (no short---------
   //--- circuit-skipping of the one that didn't determine the outcome) ----
   SRegimeHysteresisState state4;
   MRE_InitHysteresisState(state4);
   SRegimeGateResult r4 = RGC_ComposeGates(state4, REGIME_COMPRESSION, true, true, "EVT999", 2);
   Check("both gates active: effective regime is UNTRADEABLE (priority), not NEWS_BLACKOUT",
         r4.effective_regime == REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY);
   Check("both gates active: spread/liquidity flag still reported",
         r4.spread_liquidity_gate_active);
   Check("both gates active: news flag STILL reported too (not silently dropped)",
         r4.news_gate_active);
   Check("both gates active: triggering_event_id still passed through even though "
         "spread/liquidity determined the effective regime",
         r4.news_triggering_event_id == "EVT999");

   //--- 5. A gate clearing on a later bar: hysteresis keeps reporting the --
   //--- PRIOR confirmed (gated) regime until a fresh required_bars run of --
   //--- clean reads actually confirms the new one -- **corrected, 2026-07-22
   //--- Codex review finding (seventh round, P0 finding 7): this test
   //--- previously asserted the FIRST clean read already stops reporting
   //--- UNTRADEABLE, on the mistaken assumption that "has_confirmed" resets
   //--- while a switch is merely pending. It does not -- MRE_ApplyHysteresis's
   //--- own "return state.has_confirmed ? state.confirmed_regime :
   //--- TRANSITION_OR_UNCERTAIN" branch only ever reports TRANSITION before
   //--- the VERY FIRST confirmation this state has ever made; once
   //--- has_confirmed is true (as it is here, from the earlier bypass call),
   //--- an unconfirmed pending switch correctly keeps reporting the OLD
   //--- confirmed regime -- that is hysteresis's entire purpose (never flap
   //--- to a merely-pending read). The previous assertion was therefore
   //--- deterministically false and could never have passed; fixed to match
   //--- MRE_ApplyHysteresis's own real, documented behavior.**
   SRegimeHysteresisState state5;
   MRE_InitHysteresisState(state5);
   RGC_ComposeGates(state5, REGIME_RANGING, true, false, "", 2); // gate active, bypassed
   SRegimeGateResult r5a = RGC_ComposeGates(state5, REGIME_RANGING, false, false, "", 2);
   Check("gate clears: first clean read still reports the PRIOR confirmed "
         "(gated) regime -- hysteresis has not yet confirmed the switch",
         r5a.effective_regime == REGIME_UNTRADEABLE_SPREAD_OR_LIQUIDITY);
   SRegimeGateResult r5b = RGC_ComposeGates(state5, REGIME_RANGING, false, false, "", 2);
   Check("gate clears: second consecutive clean RANGING read confirms RANGING",
         r5b.effective_regime == REGIME_RANGING);

   PrintFormat("=== TASK-034 RegimeGateComposer test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
