//+------------------------------------------------------------------+
//| Export_TradeHistory.mq5                                          |
//| Themba Adaptive Intraday Engine — TASK-037 real-data export tool   |
//|                                                                    |
//| Reads MT5's own Deals history for [InpFromDate, InpToDate] and       |
//| writes trades.csv in EXACTLY the schema                               |
//| analysis/analyse_baseline.py + analysis/join_signal_to_outcome.py       |
//| already document: trade_id, symbol, is_long, entry_time, exit_time,      |
//| entry_price, exit_price, stop_price, profit, order_id, deal_id.             |
//|                                                                    |
//| One row per CLOSING FILL (OUT/OUT_BY/INOUT deal), not per position, per  |
//| join_signal_to_outcome.py's own documented cardinality requirement -- a    |
//| position closed across multiple partial-close deals produces multiple       |
//| rows sharing the same order_id (position_id), each with its own unique       |
//| trade_id/deal_id; join_signal_to_outcome.py aggregates them back into ONE     |
//| joined row per position on its own side.                                        |
//|                                                                    |
//| **Rewritten, 2026-07-22 (Codex review finding, seventh round, P0 finding |
//| 9):** this is now a thin LIVE WRAPPER (matching this project's own          |
//| established "pure core + live wrapper" split, e.g. ExitOrchestrator.mqh)      |
//| around TradeHistoryAggregator.mqh's TA_ProcessDeal, which does the real         |
//| position-lifecycle reconstruction. The previous version indexed every            |
//| opening deal but kept only the FIRST one found per position_id -- a                 |
//| position opened across multiple broker-side partial fills (same order,       |
//| same position_id, several IN deals) silently used only the first fill's         |
//| price, ignored the others' volume/cost, and read stop_price from the               |
//| CLOSING deal's own DEAL_SL (which reflects any trailing/break-even                    |
//| modification made since entry, not the original risk). See                              |
//| TradeHistoryAggregator.mqh's own header for the full corrected design.**                    |
//|                                                                    |
//| **order_id = MT5's POSITION_IDENTIFIER (DEAL_POSITION_ID) -- NEVER the  |
//| position ticket, matching this project's own P0-1 identity fix              |
//| (OrderManager.mqh's SOrderOpenResult).**                                        |
//|                                                                    |
//| **Net-P/L formula, per TASK-037 Specification item 1, EXTENDED by the   |
//| seventh-round fix above: net = exit_deal_profit + exit_deal_commission +    |
//| exit_deal_swap + exit_deal_fee + (this leg's total entry-side                    |
//| commission+swap+fee, allocated proportionally to the volume THIS row is             |
//| closing). Verifying this formula against a real MT5 Deals export remains               |
//| the user's own step (this sandbox cannot run a live/demo terminal) --                     |
//| explicitly flagged, not silently claimed done.**                                             |
//|                                                                    |
//| **stop_price is now read from the FIRST opening (DEAL_ENTRY_IN) deal's   |
//| own DEAL_SL for this leg -- the stop that was active on the position at      |
//| the moment it was FILLED, before any later trailing/break-even                 |
//| modification could have changed it. This is the "original submitted/            |
//| fill-time stop from durable evidence" the review asked for.**                       |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Journal/TradeHistoryAggregator.mqh"

input datetime InpFromDate     = D'2020.01.01 00:00:00';
input datetime InpToDate       = 0; // 0 = now
input long     InpExportMagic  = 0; // 0 = every magic (no filter)
input string   InpExportSymbol = ""; // "" = every symbol (no filter)
input string   InpOutputFile   = "ThembaEA\\Export\\trades.csv";

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition) { PrintFormat("PASS: %s", label); g_pass++; }
   else          { PrintFormat("FAIL: %s", label); g_fail++; }
  }

// **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 10):**
// HistoryDealGetInteger(..., DEAL_TIME) is trade-SERVER time, per MetaQuotes'
// own documentation -- this export previously formatted it directly with a
// "Z" (UTC) suffix, mislabeling every entry_time/exit_time on a non-UTC
// broker. ServerTimeToUtc converts using the CURRENT server-GMT offset, a
// stated approximation for historical deals recorded before the most recent
// DST transition (MQL5 exposes no broker-specific historical timezone
// database) -- not silently assumed exact.
datetime ServerTimeToUtc(const datetime server_time)
  {
   long offset_seconds = (long)TimeTradeServer() - (long)TimeGMT();
   return (datetime)((long)server_time - offset_seconds);
  }

string Iso8601Utc(const datetime server_time)
  {
   datetime utc = ServerTimeToUtc(server_time);
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", dt.year, dt.mon, dt.day, dt.hour, dt.min,
                        dt.sec);
  }

void OnStart()
  {
   Print("=== TASK-037 Export_TradeHistory start ===");

   datetime to_date = (InpToDate == 0) ? TimeCurrent() : InpToDate;
   if(!HistorySelect(InpFromDate, to_date))
     {
      Print("ABORT: HistorySelect failed -- cannot read deal history.");
      return;
     }

   int total_deals = HistoryDealsTotal();
   PrintFormat("INFO: %d total deals in the selected history window.", total_deals);

   int handle = FileOpen(InpOutputFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ, 0,
                          CP_UTF8);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("ABORT: could not open '%s' for writing (error=%d).", InpOutputFile,
                  GetLastError());
      return;
     }

   FileWriteString(handle, "trade_id,symbol,is_long,entry_time,exit_time,entry_price,"
                           "exit_price,stop_price,profit,order_id,deal_id\r\n");

   // Deals are read from HistorySelect in chronological order (MetaQuotes'
   // own documented ordering) -- TA_ProcessDeal relies on that to build
   // each position_id's leg incrementally as its constituent deals appear.
   SPositionLeg legs[];
   int rows_written = 0;

   for(int i = 0; i < total_deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(InpExportMagic != 0 && HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpExportMagic)
         continue;
      if(InpExportSymbol != "" && HistoryDealGetString(ticket, DEAL_SYMBOL) != InpExportSymbol)
         continue;

      SDealRecord deal;
      deal.ticket = ticket;
      deal.position_id = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      deal.symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      deal.entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      deal.deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      deal.volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      deal.price = HistoryDealGetDouble(ticket, DEAL_PRICE);
      deal.time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      deal.stop_loss = HistoryDealGetDouble(ticket, DEAL_SL);
      deal.commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      deal.swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      deal.fee = HistoryDealGetDouble(ticket, DEAL_FEE);
      deal.raw_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

      STradeRow row;
      string warning;
      bool produced = TA_ProcessDeal(legs, deal, row, warning);
      if(warning != "")
         PrintFormat("WARNING: %s", warning);
      if(!produced)
         continue;

      string line = StringFormat(
         "T%I64u,%s,%s,%s,%s,%.8f,%.8f,%.8f,%.8f,%I64u,%I64u\r\n", row.ticket, row.symbol,
         row.is_long ? "true" : "false", Iso8601Utc(row.entry_time), Iso8601Utc(row.exit_time),
         row.entry_price, row.exit_price, row.stop_price, row.profit, row.position_id,
         row.ticket);
      FileWriteString(handle, line);
      rows_written++;
     }

   FileClose(handle);
   PrintFormat("INFO: wrote %d trade row(s) to '%s'.", rows_written, InpOutputFile);

   Check("at least the file itself was written (may legitimately be 0 rows if no closed "
         "position exists in the selected window)", true);
   PrintFormat("=== TASK-037 Export_TradeHistory complete: %d row(s) written -- verify the "
               "net-P/L formula against this export by hand for at least one real deal before "
               "trusting downstream analysis (this sandbox cannot run a live/demo terminal to "
               "do that verification itself) ===", rows_written);
  }
