//+------------------------------------------------------------------+
//| TradeHistoryAggregator.mqh                                       |
//| Themba Adaptive Intraday Engine — Journal                         |
//|                                                                    |
//| **Added, 2026-07-22 (Codex review finding, seventh round, P0 finding    |
//| 9):** the PURE, deterministic core extracted out of                         |
//| Export_TradeHistory.mq5's own history-reconstruction logic, matching             |
//| this project's own established "pure core + live wrapper" split (see              |
//| ExitOrchestrator.mqh, IntentManager.mqh) -- this is what makes the                    |
//| position-lifecycle math genuinely unit-testable without a live/demo                     |
//| terminal (this sandbox cannot run one; MT5's HistoryDealGet* functions                     |
//| only ever return real, currently-loaded account history).                                     |
//|                                                                    |
//| Reconstructs one position_id's lifecycle as a running LEG through a         |
//| single chronological pass over a deal stream, fed one SDealRecord at a       |
//| time via TA_ProcessDeal: every DEAL_ENTRY_IN deal accumulates into a           |
//| volume-weighted entry price and a summed entry-side cost pool; every            |
//| DEAL_ENTRY_OUT/OUT_BY/INOUT deal closes some or all of the leg's                  |
//| currently open volume and (if any volume was actually closed) emits one            |
//| STradeRow using the LEG's own aggregated entry data -- never anything                |
//| read off the closing deal itself other than its own exit price/time/costs.               |
//|                                                                    |
//| DEAL_ENTRY_INOUT (a reversal: one deal that closes the existing leg AND |
//| opens a new one in the opposite direction) closes ALL of the leg's           |
//| remaining open volume -- that half is well-defined. The NEW reversed leg       |
//| that same deal also opens is NOT tracked (a stated, bounded limitation):         |
//| MT5's exact position-identifier assignment across a reversal cannot be             |
//| verified without a live terminal, and this project's own EA never                    |
//| produces one under its own magic number (AttemptOrderSubmission's own                   |
//| no-add-on/no-concurrent-position gate refuses any submission while a                        |
//| position is already open). A caller-visible warning_out flags this rather                    |
//| than silently guessing.                                                                          |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| One position_id's running lifecycle state. Never reset except when   |
//| the leg's open_volume reaches zero (a genuine full close), so a         |
//| partial close mid-leg still allocates entry-side cost correctly           |
//| against the leg's TOTAL entry volume/cost, not just what remains open       |
//| at the moment of that particular close.                                       |
//+------------------------------------------------------------------+
struct SPositionLeg
  {
   ulong    position_id;
   string   symbol;
   double   open_volume;              // currently open volume for this leg
   double   entry_volume_total;       // total volume ever entered into this leg
   double   entry_price_weighted_sum; // sum(price * volume) over constituent IN deals
   double   entry_cost_total;         // sum(commission+swap+fee) over constituent IN deals
   datetime entry_time;               // time of the FIRST IN deal that opened this leg
   double   entry_stop;               // DEAL_SL of the FIRST IN deal (fill-time original stop)
  };

//+------------------------------------------------------------------+
//| Plain-data mirror of the deal fields TA_ProcessDeal needs -- a caller   |
//| populates this from HistoryDealGetXxx (or, in a test, fabricates it      |
//| directly) so the aggregation logic itself never calls into live          |
//| history.                                                                  |
//+------------------------------------------------------------------+
struct SDealRecord
  {
   ulong           ticket;
   ulong           position_id;
   string          symbol;
   ENUM_DEAL_ENTRY entry;
   ENUM_DEAL_TYPE  deal_type;
   double          volume;
   double          price;
   datetime        time;
   double          stop_loss;
   double          commission;
   double          swap;
   double          fee;
   double          raw_profit;
  };

//+------------------------------------------------------------------+
//| One emitted trade row -- the exact field set Export_TradeHistory.mq5's  |
//| own CSV schema needs.                                                    |
//+------------------------------------------------------------------+
struct STradeRow
  {
   ulong    ticket;
   ulong    position_id;
   string   symbol;
   bool     is_long;
   datetime entry_time;
   datetime exit_time;
   double   entry_price;
   double   exit_price;
   double   stop_price;
   double   profit;
  };

int TA_FindLegIndex(const SPositionLeg &legs[], const ulong position_id)
  {
   for(int i = 0; i < ArraySize(legs); i++)
      if(legs[i].position_id == position_id)
         return i;
   return -1;
  }

int TA_CreateLeg(SPositionLeg &legs[], const ulong position_id, const string symbol,
                  const datetime entry_time, const double entry_stop)
  {
   int n = ArraySize(legs);
   ArrayResize(legs, n + 1);
   legs[n].position_id = position_id;
   legs[n].symbol = symbol;
   legs[n].open_volume = 0.0;
   legs[n].entry_volume_total = 0.0;
   legs[n].entry_price_weighted_sum = 0.0;
   legs[n].entry_cost_total = 0.0;
   legs[n].entry_time = entry_time;
   legs[n].entry_stop = entry_stop;
   return n;
  }

void TA_RemoveLeg(SPositionLeg &legs[], const int index)
  {
   int last = ArraySize(legs) - 1;
   if(index != last)
      legs[index] = legs[last];
   ArrayResize(legs, last);
  }

//+------------------------------------------------------------------+
//| PURE — processes exactly one deal against the caller-owned 'legs'      |
//| array (mutated in place, mirrors every other caller-owned-state          |
//| module in this project, e.g. MarketRegimeEngine.mqh's                      |
//| SRegimeHysteresisState). Returns true iff this deal produced a             |
//| completed closing row (written to 'row_out'); an IN deal, or a closing       |
//| deal that only partially/fully failed to match an open leg, returns          |
//| false. 'warning_out' is set to a non-empty, human-readable string on          |
//| any data anomaly worth a caller's attention (an orphaned closing deal,          |
//| a volume mismatch, or an untracked reversal remainder) -- never silently         |
//| swallowed.                                                                         |
//+------------------------------------------------------------------+
bool TA_ProcessDeal(SPositionLeg &legs[], const SDealRecord &deal, STradeRow &row_out,
                     string &warning_out)
  {
   warning_out = "";

   if(deal.position_id == 0)
      return false; // not a real position (e.g. a balance/credit deal)

   double deal_cost = deal.commission + deal.swap + deal.fee;

   if(deal.entry == DEAL_ENTRY_IN)
     {
      int idx = TA_FindLegIndex(legs, deal.position_id);
      if(idx == -1)
         idx = TA_CreateLeg(legs, deal.position_id, deal.symbol, deal.time, deal.stop_loss);
      legs[idx].open_volume += deal.volume;
      legs[idx].entry_volume_total += deal.volume;
      legs[idx].entry_price_weighted_sum += deal.price * deal.volume;
      legs[idx].entry_cost_total += deal_cost;
      return false;
     }

   if(deal.entry != DEAL_ENTRY_OUT && deal.entry != DEAL_ENTRY_OUT_BY &&
      deal.entry != DEAL_ENTRY_INOUT)
      return false; // not a fill this aggregator understands (e.g. DEAL_ENTRY_STATE)

   int idx = TA_FindLegIndex(legs, deal.position_id);
   if(idx == -1)
     {
      warning_out = StringFormat(
         "closing deal #%I64u (position_id=%I64u) has no matching open leg -- its entry likely "
         "predates the export window.", deal.ticket, deal.position_id);
      return false;
     }

   double close_volume;
   if(deal.entry == DEAL_ENTRY_INOUT)
     {
      // See this file's own header comment: a reversal deal closes ALL of
      // the leg's remaining open volume; any excess volume in the same
      // deal opens a new, untracked reversed leg.
      close_volume = legs[idx].open_volume;
      if(deal.volume > close_volume + 0.0000001)
         warning_out = StringFormat(
            "reversal (INOUT) deal #%I64u (position_id=%I64u) closed the full existing leg "
            "(volume=%.4f) but its own deal volume (%.4f) exceeds that -- a NEW reversed "
            "position was also opened by this same deal; this exporter does NOT track that new "
            "leg (stated, bounded limitation).", deal.ticket, deal.position_id, close_volume,
            deal.volume);
     }
   else
     {
      close_volume = MathMin(deal.volume, legs[idx].open_volume);
      if(deal.volume > legs[idx].open_volume + 0.0000001)
         warning_out = StringFormat(
            "closing deal #%I64u (position_id=%I64u) volume (%.4f) exceeds this leg's own "
            "tracked open volume (%.4f) -- clamped.", deal.ticket, deal.position_id, deal.volume,
            legs[idx].open_volume);
     }

   bool produced_row = false;
   if(close_volume > 0.0)
     {
      row_out.ticket = deal.ticket;
      row_out.position_id = deal.position_id;
      row_out.symbol = deal.symbol;
      row_out.is_long = (deal.deal_type == DEAL_TYPE_SELL);
      row_out.entry_time = legs[idx].entry_time;
      row_out.exit_time = deal.time;
      row_out.entry_price = legs[idx].entry_price_weighted_sum / legs[idx].entry_volume_total;
      row_out.exit_price = deal.price;
      row_out.stop_price = legs[idx].entry_stop;

      double entry_cost_alloc = legs[idx].entry_cost_total *
                                 (close_volume / legs[idx].entry_volume_total);
      row_out.profit = deal.raw_profit + deal_cost + entry_cost_alloc;

      produced_row = true;
     }

   legs[idx].open_volume -= close_volume;
   if(legs[idx].open_volume <= 0.0000001)
      TA_RemoveLeg(legs, idx);

   return produced_row;
  }
