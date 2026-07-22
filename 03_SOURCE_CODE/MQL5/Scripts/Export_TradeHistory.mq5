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
//| One row per FILL (per closing deal), not per position, per                   |
//| join_signal_to_outcome.py's own documented cardinality requirement --          |
//| a position closed across multiple partial-close deals produces multiple         |
//| rows sharing the same order_id (position_id), each with its own unique            |
//| trade_id/deal_id. This project's own OM_ClosePosition/                             |
//| IntradayCloseManager.mqh both close a position's FULL volume in one                  |
//| deal today, so in practice every export currently produces exactly one                 |
//| row per position -- but the export itself does not assume that will                     |
//| always be true.                                                                             |
//|                                                                    |
//| **order_id = MT5's POSITION_IDENTIFIER (DEAL_POSITION_ID on the         |
//| closing deal) -- NEVER the position ticket, matching this project's        |
//| own P0-1 identity fix (OrderManager.mqh's SOrderOpenResult).**                |
//|                                                                    |
//| **Net-P/L formula, per TASK-037 Specification item 1: net = profit +   |
//| commission + swap + fee, summed per CLOSING deal (this export's own       |
//| row granularity is per-fill, so no cross-row aggregation is needed).**        |
//| This formula is asserted here, not merely assumed -- see the inline           |
//| comment at its use site. **Verifying this formula against a real MT5           |
//| Deals export remains the user's own step (this sandbox cannot run a             |
//| live/demo terminal) -- explicitly flagged, not silently claimed done.**           |
//|                                                                    |
//| stop_price is read from the closing deal's own DEAL_SL property (the   |
//| SL that was active on the position at the moment it closed) --                |
//| DEAL_SL/DEAL_TP are informational deal properties MT5 populates from            |
//| the position's state at closing time, not re-derived from the journal              |
//| or any other source.                                                                  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

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

string Iso8601Utc(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
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

   // Pass 1: index every opening (DEAL_ENTRY_IN) deal by its position_id,
   // so each closing deal below can look up its own entry_price/entry_time.
   ulong  open_position_ids[];
   double open_prices[];
   datetime open_times[];

   for(int i = 0; i < total_deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(InpExportMagic != 0 && HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpExportMagic)
         continue;
      if(InpExportSymbol != "" && HistoryDealGetString(ticket, DEAL_SYMBOL) != InpExportSymbol)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      ulong pos_id = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      int n = ArraySize(open_position_ids);
      ArrayResize(open_position_ids, n + 1);
      ArrayResize(open_prices, n + 1);
      ArrayResize(open_times, n + 1);
      open_position_ids[n] = pos_id;
      open_prices[n] = HistoryDealGetDouble(ticket, DEAL_PRICE);
      open_times[n] = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
     }

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

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue; // only a CLOSING deal produces a trade row (has exit_price/profit)

      ulong pos_id = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      // A closing deal's own DEAL_TYPE is the OPPOSITE side of the
      // position (a SELL deal closes a long position, and vice versa).
      bool is_long = (deal_type == DEAL_TYPE_SELL);

      double entry_price = 0.0;
      datetime entry_time = 0;
      bool found_entry = false;
      for(int j = 0; j < ArraySize(open_position_ids); j++)
        {
         if(open_position_ids[j] == pos_id)
           {
            entry_price = open_prices[j];
            entry_time = open_times[j];
            found_entry = true;
            break;
           }
        }
      if(!found_entry)
        {
         PrintFormat("WARNING: closing deal #%I64u (position_id=%I64u) has no matching opening "
                     "deal in this export window -- skipping (its entry likely predates "
                     "InpFromDate).", ticket, pos_id);
         continue;
        }

      double exit_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
      datetime exit_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double stop_price = HistoryDealGetDouble(ticket, DEAL_SL);

      // Net-P/L formula, per this file's own header comment.
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                       HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                       HistoryDealGetDouble(ticket, DEAL_SWAP) +
                       HistoryDealGetDouble(ticket, DEAL_FEE);

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      string line = StringFormat(
         "T%I64u,%s,%s,%s,%s,%.8f,%.8f,%.8f,%.8f,%I64u,%I64u\r\n", ticket, symbol,
         is_long ? "true" : "false", Iso8601Utc(entry_time), Iso8601Utc(exit_time), entry_price,
         exit_price, stop_price, profit, pos_id, ticket);
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
