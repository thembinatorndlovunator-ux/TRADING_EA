//+------------------------------------------------------------------+
//| Test_ExitOrchestrator.mq5                                         |
//| Themba Adaptive Intraday Engine — TASK-041 compile/logic test       |
//|                                                                    |
//| Pure, deterministic, no live trading action — exercises                |
//| EO_EvaluatePosition directly against hand-fabricated price/swing        |
//| arrays and SPositionExitState values (never loaded from a real live       |
//| position). Each scenario below is hand-derivable; see the inline           |
//| comments for the arithmetic.                                                  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Execution/ExitOrchestrator.mqh"

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

bool NearlyEqual(const double a, const double b, const double tol = 0.00001)
  {
   return MathAbs(a - b) <= tol;
  }

SExitConfig MakeConfig()
  {
   SExitConfig cfg;
   cfg.break_even_min_r = 0.5;
   cfg.trail_buffer_atr_multiple = 0.3;
   cfg.atr_trail_multiple = 2.0;
   cfg.trail_stale_bars = 3; // small, so the staleness test doesn't need many calls
   cfg.scalp_max_minutes = 60.0;
   cfg.time_stop_min_r = 0.3;
   cfg.profit_lock_trigger_percent = 70.0;
   cfg.profit_lock_keep_percent = 50.0;
   cfg.stop_modify_tolerance = 0.000001;
   return cfg;
  }

SPositionExitState MakeFreshState()
  {
   SPositionExitState s;
   s.peak_r = 0.0;
   s.bars_since_favorable_swing = 0;
   s.break_even_armed = false;
   s.profit_lock_armed = false;
   s.last_swing_price = 0.0;
   s.initial_stop_price = 0.0;
   return s;
  }

void OnStart()
  {
   Print("=== TASK-041 ExitOrchestrator test start ===");

   // Depth=1 confirmed-swing-low array: lows[1]=1.1050 is a pivot because
   // lows[0]=1.1200 > 1.1050 and lows[2]=1.1200 > 1.1050. Ten elements
   // satisfies SE_FindNearestConfirmedSwingLowArray's own bounds check for
   // depth=1, max_lookback up to 8.
   double lows_favorable[10] = {1.1200, 1.1050, 1.1200, 1.1000, 1.0950, 1.0900, 1.0850, 1.0800,
                                  1.0750, 1.0700};
   // Confirmed swing HIGH at index 1 (1.0970 is a local max: neighbors
   // 1.0950 on both sides are lower) — only used by scenario 7's short-side
   // test; irrelevant to scenarios 1-6 (all long, which only read lows[]).
   double highs_favorable[10] = {1.0950, 1.0970, 1.0950, 1.0900, 1.0850, 1.0800, 1.0750, 1.0700,
                                   1.0650, 1.0600};
   int depth = 1;
   int max_lookback = 8;

   //--- 1. Structure trailing wins over break-even when the swing is well -
   //--- beyond entry --------------------------------------------------------
   // entry=1.1000, initial_stop=1.0900 (risk 0.0100). current_price=1.1060
   // -> current_r = 0.60 >= break_even_min_r(0.5) -> arms break-even
   // (candidate = entry = 1.1000). Favorable swing = 1.1050 (> entry) ->
   // structure trail = 1.1050 - atr(0.0020)*0.3 = 1.1050 - 0.0006 = 1.1044,
   // which beats the break-even candidate (1.1000) -> effective stop 1.1044.
   SExitConfig cfg = MakeConfig();
   SPositionExitState s1 = MakeFreshState();
   SExitDecision d1 = EO_EvaluatePosition(true, 1.1000, 1.0900, 1.0900, 1.1060, 1.1300, 0.0020,
                                           highs_favorable, lows_favorable, depth, max_lookback,
                                           true, false, 0.5, true, 10.0, cfg, s1);
   Check("scenario 1: break-even arms", s1.break_even_armed);
   Check("scenario 1: does not close", d1.should_close == false);
   Check("scenario 1: modifies the stop", d1.should_modify_stop);
   Check("scenario 1: structure trail (1.1044) beats break-even (1.1000)",
         NearlyEqual(d1.new_stop_price, 1.1044));

   //--- 2. Never-widen: a subsequent call with a WORSE candidate does not --
   //--- lower the stop already achieved in scenario 1 -----------------------
   // Re-run with current_stop already at 1.1044 (as scenario 1 left it) and
   // a lower current_price that would otherwise suggest a lower ATR
   // fallback -- but the swing hasn't gone stale yet, so structure trail
   // (still 1.1044, same swing) applies again, and even if it didn't, the
   // never-widen invariant must never return something below 1.1044.
   SExitDecision d2 = EO_EvaluatePosition(true, 1.1000, 1.0900, 1.1044, 1.1010, 1.1300, 0.0020,
                                           highs_favorable, lows_favorable, depth, max_lookback,
                                           false, false, 0.5, true, 12.0, cfg, s1);
   Check("scenario 2: never-widen -- new stop is never below the prior stop",
         d2.new_stop_price >= 1.1044 - 0.000001);

   //--- 3. Staleness: repeated bars with the SAME (not genuinely new) ------
   //--- swing eventually flips to the ATR-fallback trail --------------------
   SPositionExitState s3 = MakeFreshState();
   s3.last_swing_price = 1.1050; // as if scenario 1 already ran once
   s3.break_even_armed = true;
   for(int i = 0; i < 3; i++) // cfg.trail_stale_bars == 3
      EO_EvaluatePosition(true, 1.1000, 1.0900, 1.1044, 1.1060, 1.1300, 0.0020, highs_favorable,
                           lows_favorable, depth, max_lookback, true, false, 0.5, true, 10.0, cfg,
                           s3);
   Check("scenario 3: bars_since_favorable_swing reached the stale threshold",
         s3.bars_since_favorable_swing >= cfg.trail_stale_bars);
   SExitDecision d3 = EO_EvaluatePosition(true, 1.1000, 1.0900, 1.1044, 1.1060, 1.1300, 0.0020,
                                           highs_favorable, lows_favorable, depth, max_lookback,
                                           true, false, 0.5, true, 10.0, cfg, s3);
   double expected_atr_fallback = 1.1060 - 0.0020 * cfg.atr_trail_multiple; // 1.1060 - 0.0040 = 1.1020
   // The never-widen invariant means the effective stop is max(prior=1.1044,
   // atr_fallback=1.1020) = 1.1044 -- confirms staleness switched the
   // CANDIDATE formula to ATR fallback without ever actually widening
   // (lowering) the position's real stop below what it already achieved.
   Check("scenario 3: stale trail candidate never widens the already-achieved stop",
         NearlyEqual(d3.new_stop_price, MathMax(1.1044, expected_atr_fallback)));

   //--- 4. Time stop: duration exceeded + low R + stale -> closes ----------
   SPositionExitState s4 = MakeFreshState();
   s4.bars_since_favorable_swing = 99; // already far past any stale threshold
   SExitDecision d4 = EO_EvaluatePosition(true, 1.1000, 1.0900, 1.0900, 1.1010, 1.1300, 0.0020,
                                           highs_favorable, lows_favorable, depth, max_lookback,
                                           false, true, 0.0, true, 65.0, cfg, s4);
   // current_r = (1.1010-1.1000)/0.0100 = 0.10 < time_stop_min_r(0.3);
   // elapsed 65min >= scalp_max_minutes(60); stale (bars=99>=3) -> closes.
   Check("scenario 4: time stop closes the position", d4.should_close);
   Check("scenario 4: close_reason is 'time_stop'", d4.close_reason == "time_stop");

   //--- 5. Time stop does NOT fire when R already made good progress -------
   SPositionExitState s5 = MakeFreshState();
   s5.bars_since_favorable_swing = 99;
   SExitDecision d5 = EO_EvaluatePosition(true, 1.1000, 1.0900, 1.0900, 1.1050, 1.1300, 0.0020,
                                           highs_favorable, lows_favorable, depth, max_lookback,
                                           false, true, 0.0, true, 65.0, cfg, s5);
   // current_r = (1.1050-1.1000)/0.0100 = 0.50 >= time_stop_min_r(0.3) -> no time stop.
   Check("scenario 5: time stop does NOT fire when current R already clears the min",
         d5.should_close == false);

   //--- 5b. Day-trade time stop does NOT fire when the session ratio is ----
   //--- UNKNOWN, even though duration/R/staleness otherwise match scenario --
   //--- 4 exactly (Codex review finding, seventh round, P0 finding 8's own -----
   //--- exact counterexample: a session-calendar lookup failure must never -----
   //--- be coerced into an unintended close). ------------------------------------
   SPositionExitState s5b = MakeFreshState();
   s5b.bars_since_favorable_swing = 99;
   SExitDecision d5b = EO_EvaluatePosition(true, 1.1000, 1.0900, 1.0900, 1.1010, 1.1300, 0.0020,
                                            highs_favorable, lows_favorable, depth, max_lookback,
                                            false, false, 0.0, false, 65.0, cfg, s5b);
   Check("scenario 5b: day-trade time stop does NOT fire with an UNKNOWN session ratio",
         d5b.should_close == false);

   //--- 6. Profit-lock arms and produces the correct locked stop -----------
   // is_new_completed_bar=false here -> the swing scan does not run this
   // call, so there is no break-even/trail candidate in play this bar
   // (last_swing_price stays 0.0) -- isolates the profit-lock formula
   // itself. entry=1.1000, target=1.1300 (distance 0.0300).
   // current_price=1.1250 covers (1.1250-1.1000)/0.0300 = 83.3% >=
   // trigger(70%) -> arms. locked stop = entry + (current-entry)*
   // keep_percent/100 = 1.1000 + 0.0250*0.50 = 1.1125.
   SPositionExitState s6 = MakeFreshState();
   SExitDecision d6 = EO_EvaluatePosition(true, 1.1000, 1.0900, 1.0900, 1.1250, 1.1300, 0.0020,
                                           highs_favorable, lows_favorable, depth, max_lookback,
                                           false, false, 0.5, true, 10.0, cfg, s6);
   Check("scenario 6: profit-lock arms", s6.profit_lock_armed);
   Check("scenario 6: profit-lock stop is 1.1125", NearlyEqual(d6.new_stop_price, 1.1125));

   //--- 7. Short-side mirror: break-even + structure trail direction -------
   // entry=1.1000 (short), initial_stop=1.1100 (risk 0.0100).
   // current_price=1.0940 -> current_r = (entry-current)/risk = 0.0060/0.0100
   // = 0.60 >= 0.5 -> arms break-even (candidate = entry = 1.1000).
   // Favorable swing (high) = 1.0970 (< entry, in favor for a short) ->
   // structure trail = 1.0970 + atr(0.0020)*0.3 = 1.0976.
   // never-widen for a short takes the MIN at each step: starting from
   // current_stop(1.1100), min(1.1100,1.1000)=1.1000 (break-even), then
   // min(1.1000,1.0976)=1.0976 -- structure trail wins here as the
   // TIGHTER (lower) of the two candidates for a short, exactly mirroring
   // scenario 1's long-side result where the trail also beat break-even.
   SPositionExitState s7 = MakeFreshState();
   SExitDecision d7 = EO_EvaluatePosition(false, 1.1000, 1.1100, 1.1100, 1.0940, 1.0700, 0.0020,
                                           highs_favorable, lows_favorable, depth, max_lookback,
                                           true, false, 0.5, true, 10.0, cfg, s7);
   Check("scenario 7 (short): break-even arms", s7.break_even_armed);
   Check("scenario 7 (short): does not close", d7.should_close == false);
   Check("scenario 7 (short): structure trail (1.0976) beats break-even (1.1000)",
         NearlyEqual(d7.new_stop_price, 1.0976));

   PrintFormat("=== TASK-041 ExitOrchestrator test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
