//+------------------------------------------------------------------+
//| SymbolProfile.mqh                                                 |
//| Themba Adaptive Intraday Engine — Market                          |
//|                                                                    |
//| Reads and caches a symbol's static broker-reported trading         |
//| properties, per TASK-002_PHASE2_SPECIFICATION.md section 8's       |
//| mandatory attach-time validation list: tick value (both the plain  |
//| and explicit loss-side variant — round-3 review found the risk     |
//| formula needed the loss-side tick value specifically, not just     |
//| the generic one), tick size, contract size, volume min/max/step,   |
//| stop level, freeze level, filling mode, and margin.                |
//|                                                                    |
//| This module only reads and stores values — it does not judge       |
//| whether they are acceptable. That judgment is BrokerValidator.mqh, |
//| kept separate so SymbolProfile stays a pure data-access module     |
//| with a single responsibility, per master-prompt section 22's       |
//| "a module must have a clear responsibility and test boundary."     |
//+------------------------------------------------------------------+
#property strict

class CSymbolProfile
  {
public:
   string   symbol;
   bool     loaded;              // true only if every field below was
                                  // read successfully from the platform —
                                  // false means at least one read failed
                                  // and no field here should be trusted.

   double   tick_value;          // SYMBOL_TRADE_TICK_VALUE
   double   tick_value_profit;   // SYMBOL_TRADE_TICK_VALUE_PROFIT
   double   tick_value_loss;     // SYMBOL_TRADE_TICK_VALUE_LOSS — the
                                  // loss-side value TASK-002 section 8's
                                  // per-position risk formula requires.
   double   tick_size;           // SYMBOL_TRADE_TICK_SIZE
   double   contract_size;       // SYMBOL_TRADE_CONTRACT_SIZE
   double   volume_min;          // SYMBOL_VOLUME_MIN
   double   volume_max;          // SYMBOL_VOLUME_MAX
   double   volume_step;         // SYMBOL_VOLUME_STEP
   double   point;               // SYMBOL_POINT
   long     digits;              // SYMBOL_DIGITS
   long     stop_level_points;   // SYMBOL_TRADE_STOPS_LEVEL
   long     freeze_level_points; // SYMBOL_TRADE_FREEZE_LEVEL
   long     filling_mode;        // SYMBOL_FILLING_MODE (bitmask; 0 is a
                                  // legitimate broker value, not itself
                                  // an error — see BrokerValidator.mqh)
   double   margin_initial;      // SYMBOL_MARGIN_INITIAL (0 is legitimate
                                  // — some brokers use leverage-based
                                  // margin instead of a fixed initial
                                  // margin per symbol)

                     CSymbolProfile() { Reset(); }

   void Reset()
     {
      symbol = "";
      loaded = false;
      tick_value = 0.0;
      tick_value_profit = 0.0;
      tick_value_loss = 0.0;
      tick_size = 0.0;
      contract_size = 0.0;
      volume_min = 0.0;
      volume_max = 0.0;
      volume_step = 0.0;
      point = 0.0;
      digits = 0;
      stop_level_points = 0;
      freeze_level_points = 0;
      filling_mode = 0;
      margin_initial = 0.0;
     }

   //--- Reads every required broker property for 'sym'. Returns true    --
   //--- only if every underlying platform call succeeded. A false       --
   //--- return means the symbol must not be traded (fail-closed, per    --
   //--- section 8) — 'loaded' mirrors the return value so callers who   --
   //--- only keep the profile object can check profile.loaded later.    --
   bool Load(const string sym)
     {
      Reset();
      symbol = sym;

      if(!SymbolSelect(sym, true))
         return false; // symbol not available from this broker at all

      bool ok = true;
      // Function call is always the left operand of && so every read
      // executes regardless of an earlier read's outcome — a caller
      // needs to know about every failed field, not just the first.
      ok = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE, tick_value) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_PROFIT, tick_value_profit) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS, tick_value_loss) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE, tick_size) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE, contract_size) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN, volume_min) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX, volume_max) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP, volume_step) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_POINT, point) && ok;
      ok = SymbolInfoDouble(sym, SYMBOL_MARGIN_INITIAL, margin_initial) && ok;

      long tmp = 0;
      ok = SymbolInfoInteger(sym, SYMBOL_DIGITS, tmp) && ok;
      digits = tmp;
      ok = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL, tmp) && ok;
      stop_level_points = tmp;
      ok = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL, tmp) && ok;
      freeze_level_points = tmp;
      ok = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE, tmp) && ok;
      filling_mode = tmp;

      loaded = ok;
      return ok;
     }
  };
