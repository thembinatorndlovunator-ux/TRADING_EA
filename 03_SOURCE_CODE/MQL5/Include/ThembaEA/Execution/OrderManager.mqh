//+------------------------------------------------------------------+
//| OrderManager.mqh                                                  |
//| Themba Adaptive Intraday Engine — Execution                        |
//|                                                                    |
//| TASK-026 — the first module in this project that can actually       |
//| submit a real order. Deliberately built and tested as its OWN         |
//| standalone module (same discipline as every other Execution/Risk     |
//| piece), NOT wired into ThembaAdaptiveIntradayEA.mq5's OnTick —         |
//| making the live EA capable of trading is a separate decision this    |
//| task does not make; see this file's own handover for the explicit    |
//| statement of that boundary.                                          |
//|                                                                    |
//| Position sizing (OM_CalculateVolume) is built directly on top of     |
//| RiskManager.mqh's already-reviewed risk-cash formula (it is the       |
//| algebraic inverse of RM_ComputeRiskCash) and RISK_POLICY.md's          |
//| "reject broker minimum volume when actual risk exceeds the cap"        |
//| rule (via RM_BrokerMinVolumeExceedsCap) — no risk math is re-derived   |
//| here, only composed. Order submission (OM_OpenPosition) and single-    |
//| ticket close (OM_ClosePosition) use CTrade with explicit result-code   |
//| checking on every operation, matching this project's fix for both      |
//| baselines' confirmed pervasive-unchecked-CTrade-result defect            |
//| (see IntradayCloseManager.mqh's header for the same citation).          |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
#include "../Market/SymbolProfile.mqh"
#include "../Risk/RiskManager.mqh"
#include "CloseInFlightTracker.mqh"

//+------------------------------------------------------------------+
//| Position-sizing result: volume plus enough detail for a caller to   |
//| log or journal the sizing decision without recomputing anything.    |
//+------------------------------------------------------------------+
struct SOrderSizingResult
  {
   double volume;              // 0.0 if rejected
   double risk_cash_target;    // equity * risk_percent / 100, before rounding
   double risk_cash_actual;    // recomputed from the final rounded volume
   bool   widened_to_minimum;  // true if volume_min exceeded the raw sized volume
   string rejection_reason;    // "" iff volume > 0.0
  };

//+------------------------------------------------------------------+
//| Sizes a position from a target risk percent and a known loss         |
//| distance (entry-to-stop, already floor/cap-validated by the caller   |
//| via RM_ValidateStopDistance — this function does not re-validate      |
//| the stop distance itself, only converts it into a volume).            |
//|                                                                       |
//| Rounds DOWN to the nearest volume_step — never up — since rounding    |
//| up would silently trade more risk than risk_percent requested.        |
//| If even the broker's minimum volume's risk exceeds risk_cap_percent,  |
//| REJECTS outright (RM_BrokerMinVolumeExceedsCap), per RISK_POLICY.md;   |
//| it never silently rounds up to force a fit. If the minimum volume's    |
//| risk is between risk_percent and risk_cap_percent, the volume is        |
//| widened to volume_min (a sanctioned widening within the cap, not a      |
//| silent breach) and 'widened_to_minimum' is set so a caller can log it.  |
//+------------------------------------------------------------------+
bool OM_CalculateVolume(const CSymbolProfile &profile, const double equity,
                         const double risk_percent, const double loss_distance,
                         const double risk_cap_percent, SOrderSizingResult &result)
  {
   result.volume = 0.0;
   result.risk_cash_target = 0.0;
   result.risk_cash_actual = 0.0;
   result.widened_to_minimum = false;
   result.rejection_reason = "";

   if(!profile.loaded)
     {
      result.rejection_reason = "symbol_profile_not_loaded";
      return false;
     }
   if(equity <= 0.0)
     {
      result.rejection_reason = "invalid_equity";
      return false;
     }
   if(loss_distance <= 0.0)
     {
      result.rejection_reason = "invalid_loss_distance";
      return false;
     }

   result.risk_cash_target = equity * risk_percent / 100.0;

   double cash_per_lot;
   if(!RM_ComputeRiskCash(profile, loss_distance, 1.0, cash_per_lot) || cash_per_lot <= 0.0)
     {
      result.rejection_reason = "invalid_cash_per_lot";
      return false;
     }

   double raw_volume = result.risk_cash_target / cash_per_lot;
   double steps = MathFloor(raw_volume / profile.volume_step + 1e-8);
   double volume = steps * profile.volume_step;

   if(volume < profile.volume_min)
     {
      double implied_percent;
      if(RM_BrokerMinVolumeExceedsCap(profile, loss_distance, equity, risk_cap_percent,
                                       implied_percent))
        {
         result.rejection_reason = StringFormat("broker_min_volume_exceeds_cap_%.2fpct",
                                                  implied_percent);
         return false;
        }
      volume = profile.volume_min;
      result.widened_to_minimum = true;
     }

   if(volume > profile.volume_max)
      volume = profile.volume_max;

   double actual_cash;
   if(!RM_ComputeRiskCash(profile, loss_distance, volume, actual_cash))
     {
      result.rejection_reason = "risk_cash_recompute_failed";
      return false;
     }

   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding
   // 3): risk_cap_percent was previously only ever checked in the
   // volume-widened-to-minimum branch above -- an ORDINARY-sized position
   // (raw_volume already >= volume_min) had NO cap enforcement at all, so
   // a misconfigured InpRiskPercentTarget exceeding InpRiskCapPercent (or
   // a drawdown-multiplier bug elsewhere) could size a position past the
   // cap with nothing to catch it. This checks the cap unconditionally,
   // for every sizing outcome, not only the widened-to-minimum path.
   if(risk_cap_percent > 0.0)
     {
      double implied_cap_percent = 100.0 * actual_cash / equity;
      if(implied_cap_percent > risk_cap_percent + 1e-6)
        {
         result.rejection_reason = StringFormat("risk_cap_percent_exceeded_%.4fpct_cap_%.4fpct",
                                                  implied_cap_percent, risk_cap_percent);
         result.volume = 0.0;
         return false;
        }
     }

   result.volume = volume;
   result.risk_cash_actual = actual_cash;
   return true;
  }

//+------------------------------------------------------------------+
//| Result of a real order-open attempt — always populated, on both       |
//| success and failure, per PROJECT_RULES.md rule 6.                     |
//+------------------------------------------------------------------+
struct SOrderOpenResult
  {
   bool   success;
   ulong  order_ticket;   // MT5's own ORDER ticket (CTrade::ResultOrder()) — populated
                            // even when position_ticket/position_id come back 0 (the
                            // TRADE_RETCODE_PLACED-not-yet-filled case). TASK-036's
                            // AsyncFillCorrelator.mqh uses this to correlate a LATER
                            // OnTradeTransaction fill back to this submission.
   ulong  deal_ticket;    // 0 on failure — MT5's DEAL_TICKET, per-fill identity
   ulong  position_ticket; // 0 on failure or if the position could not be resolved —
                            // MT5's POSITION_TICKET, valid for THIS SESSION's live API
                            // calls (PositionSelectByTicket/CTrade::PositionClose both
                            // require this exact value RIGHT NOW), but NOT guaranteed
                            // stable across the position's whole lifetime (see
                            // position_id below and this struct's own review-finding
                            // comment).
   ulong  position_id;    // 0 on failure or if the position could not be resolved —
                            // MT5's POSITION_IDENTIFIER, the DURABLE cross-reference
                            // key for journaling/Python-side joins (matches every
                            // related deal's own DEAL_POSITION_ID). Added, 2026-07-22
                            // (Codex review finding, sixth round, TASK-028's own
                            // round-6 P0 finding 1): position_ticket "can change after
                            // a server service re-open and, in netting mode, after
                            // reversal" per MT5's own documented lifecycle contract --
                            // position_id is the field MT5 documents as staying
                            // constant for the position's entire life. Use THIS field,
                            // never position_ticket, as the journal's own 'order_id'
                            // once TASK-036 wires journaling to this struct.
   double fill_price;     // 0.0 on failure
   double filled_volume;  // **Added, 2026-07-22 (Codex review finding, eighth round, P0
                            // finding 8):** the ACTUAL volume filled (CTrade::ResultVolume()) --
                            // equals the requested volume for a normal TRADE_RETCODE_DONE fill,
                            // but is LESS than requested for TRADE_RETCODE_DONE_PARTIAL (MetaQuotes
                            // code 10010, "only part of the request was completed"). 0.0 on failure
                            // or an unresolved PLACED (not-yet-filled) order. A caller MUST size
                            // any post-fill risk/journal figure off THIS field, never the originally
                            // requested 'volume' passed into this function, once retcode indicates
                            // a partial fill.
   uint   retcode;
   string rejection_reason; // "" iff success
   // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 4):
   // true iff the broker retcode itself was DONE/DONE_PARTIAL (a REAL fill
   // genuinely happened) but this function could not resolve the fill's own
   // deal/position details (HistoryDealSelect failed, the deal had no
   // DEAL_POSITION_ID yet, or the resulting position could not be found by
   // that ID) -- 'success' is deliberately left false for this case (this
   // function itself could not hand the caller a usable position_id/ticket),
   // but a caller MUST NOT treat this identically to a genuine order
   // rejection: real, live exposure exists at the broker regardless of
   // whether this process could resolve it. See OM_OpenPosition's own
   // updated comment for the full defect this closes and the required
   // caller behavior.
   bool   exposure_unresolved;
   // **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding 4):
   // true iff retcode == TRADE_RETCODE_DONE_PARTIAL AND the SAME order
   // ticket is still found in the ACTIVE (working) orders list immediately
   // after this call -- meaning the broker's own filling-mode configuration
   // for this symbol left an unfilled REMAINDER still working, not fully
   // terminal. This is possible under ORDER_FILLING_RETURN (a market order
   // can behave like a resting limit order for its unfilled remainder);
   // BrokerValidator.mqh does not yet force a specific filling mode (see
   // that module's own P0 finding 7 fix), so this cannot be ruled out
   // structurally yet. false for an ordinary DONE fill or a DONE_PARTIAL
   // under FOK/IOC (which never leaves a remainder). A caller MUST treat
   // true here like the async PLACED case (durable intent left ACTIVE,
   // AsyncFillCorrelator.mqh tracks order_ticket for the remainder's own
   // later terminal outcome), never as fully resolved.
   bool   has_live_remainder;
  };

//+------------------------------------------------------------------+
//| Submits a real market order via CTrade — the first function in this   |
//| project capable of opening a live position. Explicitly checks the     |
//| CTrade result code on every call (never assumes success from a bool    |
//| return alone, since CTrade's own bool can be true for a PLACED-but-     |
//| not-yet-DONE pending state on some brokers). Looks up the resulting     |
//| position by (symbol, magic) immediately after a successful DONE/        |
//| PLACED retcode, so a caller gets both a real position_ticket (for THIS   |
//| session's immediate close/modify calls, which the MT5 API itself         |
//| requires) and the durable position_id (for cross-session/cross-reboot    |
//| journaling identity — see SOrderOpenResult's own comment for exactly     |
//| why these two are NOT interchangeable), not just a deal ticket, to        |
//| hand to OM_ClosePosition or IntradayCloseManager.mqh's own magic-scoped    |
//| enumeration later.                                                         |
//+------------------------------------------------------------------+
bool OM_OpenPosition(const string symbol, const bool is_long, const double volume,
                      const double sl_price, const double tp_price, const long magic,
                      const string comment, SOrderOpenResult &result)
  {
   result.success = false;
   result.order_ticket = 0;
   result.deal_ticket = 0;
   result.position_ticket = 0;
   result.position_id = 0;
   result.fill_price = 0.0;
   result.filled_volume = 0.0;
   result.retcode = 0;
   result.rejection_reason = "";
   result.exposure_unresolved = false;
   result.has_live_remainder = false;

   if(volume <= 0.0)
     {
      result.rejection_reason = "invalid_volume";
      return false;
     }

   CTrade trade;
   trade.SetExpertMagicNumber(magic);

   double price = is_long ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(symbol, SYMBOL_BID);
   if(price <= 0.0)
     {
      result.rejection_reason = "invalid_market_price";
      return false;
     }

   bool ok = is_long ? trade.Buy(volume, symbol, price, sl_price, tp_price, comment)
                      : trade.Sell(volume, symbol, price, sl_price, tp_price, comment);
   result.retcode = trade.ResultRetcode();

   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 8):
   // TRADE_RETCODE_DONE_PARTIAL (MetaQuotes code 10010, "only part of the
   // request was completed") is now accepted alongside DONE and PLACED --
   // it previously fell into this failure branch, so the caller cleared its
   // durable intent and journaled an outright rejection even though PART OF
   // THE REQUESTED POSITION ACTUALLY EXISTS at the broker. That live
   // exposure was never correlated to the decision that created it and
   // never received the post-fill hard-risk check section 8 requires for
   // every real position. A partial fill is real, live exposure, not a
   // failure -- it is resolved by the SAME causally-correct DEAL_POSITION_ID
   // path as a full DONE fill below, just with a smaller ACTUAL filled
   // volume (result.filled_volume) than what was originally requested.**
   if(!ok || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED &&
              result.retcode != TRADE_RETCODE_DONE_PARTIAL))
     {
      result.rejection_reason = StringFormat("order_open_failed_retcode_%u", result.retcode);
      return false;
     }

   result.order_ticket = trade.ResultOrder();
   result.deal_ticket = trade.ResultDeal();
   result.fill_price  = trade.ResultPrice();

   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 1):
   // this previously scanned every OPEN position matching symbol+magic and
   // took the FIRST one found -- a "take the first match" heuristic that is
   // unsafe now that this EA requires a HEDGING-mode account (this same
   // round's own fix), where MULTIPLE simultaneous positions can genuinely
   // exist under the same symbol+magic (e.g. a still-closing prior position
   // whose retry loop, per the seventh round's own P0 finding 8 fix, has not
   // yet observed a broker-confirmed DONE). Scanning by symbol+magic alone
   // could silently resolve to the WRONG position -- one this order did not
   // even create.
   //
   // The deal that was JUST filled (result.deal_ticket, from
   // CTrade::ResultDeal() above) is the causally correct source: its own
   // DEAL_POSITION_ID is MT5's documented durable identity for the EXACT
   // position that deal opened or added to -- no scanning or matching
   // heuristic needed. HistoryDealSelect (not a broader HistorySelect range)
   // is sufficient to bring this single, just-created deal's own properties
   // into reach, since it is guaranteed to already be in this terminal's
   // history the instant CTrade reports it filled.
   //
   // **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding
   // 8): now also runs for TRADE_RETCODE_DONE_PARTIAL, not just DONE -- a
   // partial fill has a real deal/position exactly like a full fill does,
   // just with a smaller ACTUAL filled volume (captured below via
   // CTrade::ResultVolume(), never the originally requested 'volume').**
   // Only attempted for a SYNCHRONOUS fill (DONE or DONE_PARTIAL) -- a
   // PLACED (accepted-for-processing, not yet filled) order has no
   // deal/position yet at all; result.position_id/position_ticket correctly
   // stay 0 in that case, exactly as before, so the caller's own existing
   // async-fill correlation (AsyncFillCorrelator.mqh, keyed by order_ticket)
   // resolves it later via OnTradeTransaction, which already reads
   // DEAL_POSITION_ID from the real fill deal the same causally-correct way.
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
     {
      // **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding
      // 4): each of the three branches below previously `return false`
      // identically to an outright order rejection, even though the broker
      // retcode just checked (DONE/DONE_PARTIAL) proves a REAL FILL
      // happened -- the caller then cleared its durable intent and
      // journaled a rejection while live, unaccounted-for exposure existed
      // at the broker. 'result.exposure_unresolved' is now set true on each
      // of these paths (still returns false -- this function itself could
      // not hand back a usable position_id/ticket -- but the caller MUST
      // check this flag, per this struct's own updated comment, and treat
      // it like the async PLACED case: leave the durable intent ACTIVE
      // rather than clearing it, so a later reconciliation pass (OnInit's
      // IM_ReconcileOnRestart, or a subsequent OnTradeTransaction call once
      // the terminal's own history catches up) gets a chance to resolve
      // this same fill instead of the intent being discarded while real
      // exposure remains live and uncorrelated.**
      if(!HistoryDealSelect(result.deal_ticket))
        {
         result.rejection_reason = "fill_deal_not_found_in_history";
         result.exposure_unresolved = true;
         return false;
        }
      result.position_id = (ulong)HistoryDealGetInteger(result.deal_ticket, DEAL_POSITION_ID);
      if(result.position_id == 0)
        {
         result.rejection_reason = "fill_deal_has_no_position_id";
         result.exposure_unresolved = true;
         return false;
        }
      result.filled_volume = HistoryDealGetDouble(result.deal_ticket, DEAL_VOLUME);

      // position_ticket (needed for THIS session's immediate close/modify
      // calls, which the MT5 API itself requires) is now resolved by
      // matching the EXACT position_id just read above -- unambiguous even
      // if other positions happen to exist under the same symbol+magic,
      // unlike the previous symbol+magic-only scan.
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) != result.position_id)
            continue;
         result.position_ticket = ticket;
         break;
        }
      if(result.position_ticket == 0)
        {
         result.rejection_reason = "filled_position_not_found_by_position_id";
         result.exposure_unresolved = true;
         return false;
        }

      // See SOrderOpenResult's own has_live_remainder comment: under
      // ORDER_FILLING_RETURN, a DONE_PARTIAL market order's own unfilled
      // remainder can still be working as an active order. OrderSelect
      // finding this exact ticket in the ACTIVE orders list (not just
      // history) means it has not fully terminated yet.
      if(result.retcode == TRADE_RETCODE_DONE_PARTIAL && OrderSelect(result.order_ticket))
         result.has_live_remainder = true;
     }

   result.success = true;
   return true;
  }

//+------------------------------------------------------------------+
//| Closes a single position by ticket, verifying it actually carries     |
//| 'magic' first — refuses to close a position it does not recognize as   |
//| its own, matching IntradayCloseManager.mqh's own-magic-only rule at      |
//| the single-ticket granularity instead of the bulk one.                    |
//+------------------------------------------------------------------+
bool OM_ClosePosition(const ulong position_ticket, const long magic, string &rejection_reason)
  {
   rejection_reason = "";

   if(!PositionSelectByTicket(position_ticket))
     {
      rejection_reason = "position_not_found";
      return false;
     }
   if(PositionGetInteger(POSITION_MAGIC) != magic)
     {
      rejection_reason = "position_not_owned_by_this_magic";
      return false;
     }

   // **Added, 2026-07-22 (Codex review finding, eighth round, P1 finding
   // 13): a close already accepted-for-processing (PLACED) for this EXACT
   // position on a prior call is not resubmitted -- see
   // CloseInFlightTracker.mqh's own header for why (MetaQuotes documents
   // OnTradeTransaction's arrival order is not guaranteed, so resubmitting
   // before the first request's terminal outcome arrives can produce
   // close-order-exists/rate-limit/volume errors at the broker).**
   ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(CIFT_IsCloseInFlight(position_id))
     {
      rejection_reason = "position_close_already_in_flight";
      return false;
     }

   CTrade trade;
   trade.SetExpertMagicNumber(magic);
   bool ok = trade.PositionClose(position_ticket);
   uint retcode = trade.ResultRetcode();
   if(retcode == TRADE_RETCODE_PLACED)
      CIFT_MarkCloseInFlight(position_id);

   // **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 8):
   // TRADE_RETCODE_PLACED means "accepted for processing", not "closed" --
   // MetaQuotes documents the actual fill/close as arriving asynchronously via
   // OnTradeTransaction, in an order not guaranteed relative to this call
   // returning. Treating PLACED as a completed close let the caller believe a
   // position was gone (and clear its own tracking state) while the position
   // could still be open. Only TRADE_RETCODE_DONE is a broker-confirmed
   // terminal "closed" outcome; PLACED is surfaced as its own distinguishable
   // reason so a caller can keep retrying rather than treating it as a hard
   // failure or a success.**
   if(!ok || retcode != TRADE_RETCODE_DONE)
     {
      // **Extended, 2026-07-22 (Codex review finding, seventh round, P1
      // finding 14): TRADE_RETCODE_DONE_PARTIAL is a real, documented
      // MetaQuotes completion state -- the request executed, but only
      // PARTIAL volume actually closed (the rest remains open). It was
      // previously lumped under the generic "failed" reason, indistinguishable
      // from a genuine rejection. It is still correctly treated as "not yet
      // fully closed" (the caller's own retry-until-fully-closed loop, per
      // this round's P0 finding 8 fix, keeps retrying on the position's own
      // now-smaller remaining volume on the next tick/bar -- exactly the
      // right behavior for a real partial completion) -- only the reported
      // reason string now names it explicitly.**
      string reason_tag;
      if(retcode == TRADE_RETCODE_PLACED)
         reason_tag = "position_close_pending_confirmation";
      else if(retcode == TRADE_RETCODE_DONE_PARTIAL)
         reason_tag = "position_close_partial_remainder_still_open";
      else
         reason_tag = "position_close_failed";
      rejection_reason = StringFormat("%s_retcode_%u", reason_tag, retcode);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| TASK-041 — result of a stop-modification attempt, always populated on |
//| both success and failure, matching SOrderOpenResult's own convention.   |
//+------------------------------------------------------------------+
struct SOrderModifyResult
  {
   bool   success;
   uint   retcode;
   double actual_sl;       // whatever SL the broker actually accepted —
                             // may differ from the requested price if a
                             // broker minimum-stop-distance rule widened
                             // it further; ExitManager.mqh's own
                             // EM_ProfitLockClearsMinFloor is designed to
                             // consume exactly this actual value, not the
                             // requested one.
   string rejection_reason; // "" iff success
  };

//+------------------------------------------------------------------+
//| Modifies a single position's stop-loss by ticket, verifying it          |
//| actually carries 'magic' first (same own-magic-only discipline as       |
//| OM_ClosePosition). The take-profit is always resubmitted UNCHANGED --     |
//| this function only ever moves the stop; a caller that wants to change      |
//| the target needs a different, explicit function (none exists yet, out       |
//| of this task's scope — see ExitOrchestrator.mqh's own header for why         |
//| target re-selection is explicitly deferred).                                    |
//+------------------------------------------------------------------+
bool OM_ModifyStop(const ulong position_ticket, const long magic, const double new_sl_price,
                    SOrderModifyResult &result)
  {
   result.success = false;
   result.retcode = 0;
   result.actual_sl = 0.0;
   result.rejection_reason = "";

   if(!PositionSelectByTicket(position_ticket))
     {
      result.rejection_reason = "position_not_found";
      return false;
     }
   if(PositionGetInteger(POSITION_MAGIC) != magic)
     {
      result.rejection_reason = "position_not_owned_by_this_magic";
      return false;
     }

   double current_tp = PositionGetDouble(POSITION_TP);

   CTrade trade;
   trade.SetExpertMagicNumber(magic);
   bool ok = trade.PositionModify(position_ticket, new_sl_price, current_tp);
   result.retcode = trade.ResultRetcode();

   if(!ok || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED))
     {
      result.rejection_reason = StringFormat("position_modify_failed_retcode_%u", result.retcode);
      return false;
     }

   // Re-select and read back the ACTUALLY accepted SL — may differ from
   // new_sl_price if the broker's own minimum-stop-distance enforcement
   // widened it further (see this struct's own actual_sl comment).
   if(PositionSelectByTicket(position_ticket))
      result.actual_sl = PositionGetDouble(POSITION_SL);
   else
      result.actual_sl = new_sl_price;

   result.success = true;
   return true;
  }
