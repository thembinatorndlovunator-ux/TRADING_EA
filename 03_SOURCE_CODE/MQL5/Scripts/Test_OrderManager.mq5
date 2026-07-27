//+------------------------------------------------------------------+
//| Test_OrderManager.mq5                                             |
//| Themba Adaptive Intraday Engine — TASK-026 compile/logic test     |
//|                                                                    |
//| Tests 1-9 exercise OM_CalculateVolume with a hand-fabricated         |
//| CSymbolProfile (same round-number values as Test_RiskManager.mq5,     |
//| so results are hand-derivable) — pure, deterministic, no live         |
//| trading action.                                                       |
//|                                                                    |
//| *** Tests 10+ PLACE A REAL (MINIMUM-VOLUME) MARKET POSITION AND     |
//| IMMEDIATELY CLOSE IT *** under a dedicated, unmistakably-test-only    |
//| magic number (InpTestMagic, default 990099002 — deliberately          |
//| distinct from Test_IntradayCloseManager.mq5's 990099001). Same         |
//| safety discipline as that script: refuses to run if this magic          |
//| already has anything open, and verifies the magic is fully clear         |
//| again at the end. Run this ONLY on a demo account.                        |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/OrderManager.mqh"

input string InpTestSymbol = "EURUSD";
input long   InpTestMagic  = 990099002;

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

int CountOwnedPositions(const long magic)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == magic)
         count++;
     }
   return count;
  }

void OnStart()
  {
   Print("=== TASK-026 OrderManager test start ===");

   //--- Hand-fabricated profile: same values as Test_RiskManager.mq5 ---
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

   //--- 1. Basic sizing: risk_cash_target / cash_per_lot, rounded down --
   // equity 10000, risk 1% -> risk_cash_target = 100. loss_distance 1.00
   // -> cash_per_lot = 1.00*1*1/0.01 = 100. raw_volume = 100/100 = 1.00.
   // 1.00 is already an exact multiple of volume_step (0.01) -> volume = 1.00.
   SOrderSizingResult r1;
   bool ok1 = OM_CalculateVolume(p, 10000.0, 1.0, 1.00, 1.0, r1);
   Check("basic sizing succeeds", ok1);
   Check("basic sizing: volume == 1.00", NearlyEqual(r1.volume, 1.00));
   Check("basic sizing: risk_cash_target == 100", NearlyEqual(r1.risk_cash_target, 100.0));
   Check("basic sizing: risk_cash_actual == 100 (exact volume_step multiple)",
         NearlyEqual(r1.risk_cash_actual, 100.0));
   Check("basic sizing: not widened to minimum", r1.widened_to_minimum == false);

   //--- 2. Rounds DOWN, never up, at a non-exact step boundary -----------
   // equity 10000, risk 1% -> risk_cash_target = 100. loss_distance 3.00
   // -> cash_per_lot = 3.00*1*1/0.01 = 300. raw_volume = 100/300 = 0.3333.
   // steps = floor(0.3333/0.01) = 33 -> volume = 0.33 (never 0.34).
   SOrderSizingResult r2;
   bool ok2 = OM_CalculateVolume(p, 10000.0, 1.0, 3.00, 1.0, r2);
   Check("non-exact sizing succeeds", ok2);
   Check("non-exact sizing rounds DOWN to 0.33 (not up to 0.34)",
         NearlyEqual(r2.volume, 0.33));
   Check("non-exact sizing: risk_cash_actual < risk_cash_target (rounded down)",
         r2.risk_cash_actual < r2.risk_cash_target);

   //--- 3. Widened to volume_min when the raw size is below it, but ------
   //--- still within risk_cap_percent -------------------------------------
   // equity 1000, risk 0.1% -> risk_cash_target = 1.0. loss_distance 1.00
   // -> cash_per_lot = 100. raw_volume = 1.0/100 = 0.01 < volume_min(0.1).
   // min-volume risk_cash = 1.00*0.1*1/0.01 = 10 -> implied% = 100*10/1000=1.0%.
   // risk_cap_percent 2.0% -> 1.0% does NOT exceed cap -> widen to volume_min.
   SOrderSizingResult r3;
   bool ok3 = OM_CalculateVolume(p, 1000.0, 0.1, 1.00, 2.0, r3);
   Check("below-minimum sizing succeeds (widened, not rejected)", ok3);
   Check("below-minimum sizing: volume == volume_min (0.1)", NearlyEqual(r3.volume, 0.1));
   Check("below-minimum sizing: widened_to_minimum == true", r3.widened_to_minimum);

   //--- 4. REJECTED outright when even volume_min exceeds the cap -------
   // Same as test 3 but risk_cap_percent 0.5% -> min-volume implied 1.0% > 0.5% cap.
   SOrderSizingResult r4;
   bool ok4 = OM_CalculateVolume(p, 1000.0, 0.1, 1.00, 0.5, r4);
   Check("min-volume-exceeds-cap case is REJECTED (never rounded up)", ok4 == false);
   Check("rejected case: volume == 0.0", NearlyEqual(r4.volume, 0.0));
   Check("rejected case: rejection_reason is set",
         StringFind(r4.rejection_reason, "broker_min_volume_exceeds_cap") == 0);

   //--- 5. Clamped to volume_max on the high side -------------------------
   // equity 10,000,000, risk 100% -> risk_cash_target huge -> raw_volume huge
   // -> must clamp to volume_max (100.0), never exceed it.
   SOrderSizingResult r5;
   bool ok5 = OM_CalculateVolume(p, 10000000.0, 100.0, 1.00, 100.0, r5);
   Check("oversized sizing succeeds (clamped)", ok5);
   Check("oversized sizing: volume clamped to volume_max (100.0)",
         NearlyEqual(r5.volume, 100.0));

   //--- 5b. **Codex review finding, seventh round, P0 finding 3**: an -------
   //--- ORDINARY-sized position (not widened to minimum, not clamped to ----
   //--- volume_max) whose implied risk exceeds risk_cap_percent must be -----
   //--- REJECTED, not silently accepted -- reproduces the exact reported -----
   //--- counterexample: risk_percent=2.0% requested with risk_cap_percent=------
   //--- 1.0%. equity 10000, risk 2% -> risk_cash_target=200. loss_distance -----
   //--- 1.00 -> cash_per_lot=100. raw_volume=200/100=2.00 (already an exact ----
   //--- step multiple, no widening/clamping). implied_cap_percent = ------------
   //--- (1.00*2.00*1/0.01)/10000*100 = 2.0% > risk_cap_percent(1.0%) -> must ---
   //--- reject.
   SOrderSizingResult r5b;
   bool ok5b = OM_CalculateVolume(p, 10000.0, 2.0, 1.00, 1.0, r5b);
   Check("ordinary-sized sizing exceeding risk_cap_percent is REJECTED "
         "(previously silently accepted)", ok5b == false);
   Check("rejected-by-cap case: volume == 0.0", NearlyEqual(r5b.volume, 0.0));
   Check("rejected-by-cap case: rejection_reason names the cap",
         StringFind(r5b.rejection_reason, "risk_cap_percent_exceeded") == 0);

   //--- 5c. The SAME risk_percent/risk_cap_percent, now with cap raised to --
   //--- 3.0% (>= the implied 2.0%) -- must succeed, proving the cap check is --
   //--- not simply always-reject. -----------------------------------------------
   SOrderSizingResult r5c;
   bool ok5c = OM_CalculateVolume(p, 10000.0, 2.0, 1.00, 3.0, r5c);
   Check("the same sizing succeeds once risk_cap_percent is raised above "
         "the implied risk", ok5c);
   Check("cap-clearing case: volume == 2.00", NearlyEqual(r5c.volume, 2.00));

   //--- 6. Invalid-input guards -------------------------------------------
   SOrderSizingResult r6;
   Check("zero equity is rejected", OM_CalculateVolume(p, 0.0, 1.0, 1.00, 1.0, r6) == false);
   SOrderSizingResult r7;
   Check("zero loss_distance is rejected", OM_CalculateVolume(p, 10000.0, 1.0, 0.0, 1.0, r7) == false);
   CSymbolProfile unloaded;
   SOrderSizingResult r8;
   Check("unloaded profile is rejected",
         OM_CalculateVolume(unloaded, 10000.0, 1.0, 1.00, 1.0, r8) == false);

   //--- 7. Real-symbol live order test ------------------------------------
   PrintFormat("WARNING: about to place a real minimum-volume market "
               "position on '%s' under magic %I64d, then close it.",
               InpTestSymbol, InpTestMagic);

   int pre_positions = CountOwnedPositions(InpTestMagic);
   if(pre_positions > 0)
     {
      PrintFormat("ABORT: magic %I64d already has %d position(s) open — "
                  "refusing to run to avoid interfering with existing "
                  "state. Investigate before re-running.",
                  InpTestMagic, pre_positions);
      PrintFormat("=== TASK-026 OrderManager test complete: %d passed, %d failed "
                  "(live-order section skipped) ===", g_pass, g_fail);
      return;
     }

   CSymbolProfile real;
   if(!real.Load(InpTestSymbol))
     {
      PrintFormat("ABORT: '%s' failed to load — cannot run the live-order "
                  "section.", InpTestSymbol);
      PrintFormat("=== TASK-026 OrderManager test complete: %d passed, %d failed "
                  "(live-order section skipped) ===", g_pass, g_fail);
      return;
     }

   SOrderOpenResult open_result;
   bool opened = OM_OpenPosition(InpTestSymbol, true, real.volume_min, 0.0, 0.0,
                                  InpTestMagic, "TASK026_TEST", open_result);
   Check(StringFormat("OM_OpenPosition succeeds (retcode=%u)", open_result.retcode),
         opened && open_result.success);

   if(!opened)
     {
      PrintFormat("ABORT: could not open the test position — skipping the "
                  "remaining close-verification checks. This may indicate "
                  "the market is closed or trading is currently disabled, "
                  "not necessarily a code defect. rejection_reason=%s",
                  open_result.rejection_reason);
     }
   else
     {
      Check("opened position has a nonzero deal_ticket", open_result.deal_ticket != 0);
      // **Added, TASK-036: order_ticket must also resolve -- this is what
      // AsyncFillCorrelator.mqh keys a PLACED-but-unconfirmed submission
      // on when position_ticket/position_id come back 0.**
      Check("opened position has a nonzero order_ticket resolved",
            open_result.order_ticket != 0);
      Check("opened position has a nonzero position_ticket resolved",
            open_result.position_ticket != 0);
      // **Added, 2026-07-22 (Codex review finding, sixth round): position_id
      // (POSITION_IDENTIFIER) must also resolve -- this is the durable
      // identity TASK-036 must journal as order_id, not position_ticket
      // (see OrderManager.mqh's own SOrderOpenResult comment for why).**
      Check("opened position has a nonzero position_id resolved",
            open_result.position_id != 0);
      Check("exactly one owned position exists after opening",
            CountOwnedPositions(InpTestMagic) == 1);
      // **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding
      // 8): a full (non-partial) fill's filled_volume must equal the
      // requested volume -- TRADE_RETCODE_DONE_PARTIAL (where filled_volume
      // would be LESS than requested) needs a broker that only has partial
      // liquidity to exercise for real, which this test environment cannot
      // force deterministically; compile-verified only, matching this
      // project's established precedent for broker-fill-state-dependent
      // paths.**
      Check("a full (non-partial) fill's filled_volume equals the requested volume",
            MathAbs(open_result.filled_volume - real.volume_min) < 0.0000001);

      //--- 9. TASK-041: OM_ModifyStop moves this same live position's SL --
      double point = SymbolInfoDouble(InpTestSymbol, SYMBOL_POINT);
      long stops_level_points = SymbolInfoInteger(InpTestSymbol, SYMBOL_TRADE_STOPS_LEVEL);
      double safe_distance = MathMax((double)stops_level_points, 100.0) * point * 2.0;
      double bid = SymbolInfoDouble(InpTestSymbol, SYMBOL_BID);
      double new_sl = bid - safe_distance; // this test's position was opened long, above

      SOrderModifyResult modify_result;
      bool modified = OM_ModifyStop(open_result.position_ticket, InpTestMagic, new_sl,
                                     modify_result);
      Check(StringFormat("OM_ModifyStop succeeds (retcode=%u)", modify_result.retcode), modified);
      if(modified)
        {
         Check("OM_ModifyStop's actual_sl is nonzero", modify_result.actual_sl != 0.0);
         Check("position's live SL reflects the modification",
               PositionSelectByTicket(open_result.position_ticket) &&
               MathAbs(PositionGetDouble(POSITION_SL) - modify_result.actual_sl) < point);
        }

      //--- 10. OM_ModifyStop refuses to modify under the wrong magic ------
      SOrderModifyResult wrong_magic_modify_result;
      bool wrongly_modified = OM_ModifyStop(open_result.position_ticket, InpTestMagic + 1, new_sl,
                                             wrong_magic_modify_result);
      Check("OM_ModifyStop refuses to modify under the wrong magic", wrongly_modified == false);
      Check("wrong-magic modify rejection reason is set",
            wrong_magic_modify_result.rejection_reason == "position_not_owned_by_this_magic");

      string close_reason;
      bool closed = OM_ClosePosition(open_result.position_ticket, InpTestMagic, close_reason);
      Check("OM_ClosePosition succeeds", closed);
      Check("zero owned positions remain after closing",
            CountOwnedPositions(InpTestMagic) == 0);

      //--- 8. Refuses to close a position under the wrong magic ----------
      // Re-open one more position, then attempt to close it while
      // claiming the WRONG magic — must be refused, and the real position
      // must still be closed correctly afterward under the right magic
      // so this test never leaks state.
      SOrderOpenResult open_result2;
      bool opened2 = OM_OpenPosition(InpTestSymbol, true, real.volume_min, 0.0, 0.0,
                                      InpTestMagic, "TASK026_TEST2", open_result2);
      if(opened2)
        {
         string wrong_magic_reason;
         bool wrongly_closed = OM_ClosePosition(open_result2.position_ticket,
                                                 InpTestMagic + 1, wrong_magic_reason);
         Check("OM_ClosePosition refuses to close under the wrong magic",
               wrongly_closed == false);
         Check("wrong-magic rejection reason is set",
               wrong_magic_reason == "position_not_owned_by_this_magic");
         Check("position still exists after the refused wrong-magic close",
               CountOwnedPositions(InpTestMagic) == 1);

         string cleanup_reason;
         OM_ClosePosition(open_result2.position_ticket, InpTestMagic, cleanup_reason);
        }
     }

   //--- Final safety check: this magic must be completely clear ----------
   Check("magic is fully clear at the end of the test (no leaked state)",
         CountOwnedPositions(InpTestMagic) == 0);

   PrintFormat("=== TASK-026 OrderManager test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
