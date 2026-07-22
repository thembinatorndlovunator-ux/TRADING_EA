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
   uint   retcode;
   string rejection_reason; // "" iff success
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
   result.retcode = 0;
   result.rejection_reason = "";

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

   if(!ok || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED))
     {
      result.rejection_reason = StringFormat("order_open_failed_retcode_%u", result.retcode);
      return false;
     }

   result.order_ticket = trade.ResultOrder();
   result.deal_ticket = trade.ResultDeal();
   result.fill_price  = trade.ResultPrice();

   // Resolve the resulting position ticket by scanning this EA's own
   // magic-scoped positions on this symbol — CTrade's ResultDeal() is a
   // deal ticket, not a position ticket, and the two are not interchangeable.
   // **Fixed, 2026-07-22 (Codex review finding, sixth round, TASK-028's own
   // round-6 P0 finding 1): PositionGetTicket(i) returns POSITION_TICKET,
   // which MT5 documents as NOT guaranteed stable across a server-side
   // service re-open or (in netting mode) a reversal -- POSITION_IDENTIFIER
   // is MT5's own documented stable-for-the-whole-lifetime key. Both are
   // now captured: position_ticket for THIS session's immediate close/
   // modify calls (which the MT5 API itself requires), position_id for
   // durable journaling identity. PositionGetTicket(i) already selects
   // this position for the PositionGetInteger/PositionGetString calls
   // below, so reading POSITION_IDENTIFIER here is reading the SAME
   // position these checks already matched.**
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      result.position_ticket = ticket;
      result.position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      break;
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

   CTrade trade;
   trade.SetExpertMagicNumber(magic);
   bool ok = trade.PositionClose(position_ticket);
   uint retcode = trade.ResultRetcode();

   if(!ok || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED))
     {
      rejection_reason = StringFormat("position_close_failed_retcode_%u", retcode);
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
