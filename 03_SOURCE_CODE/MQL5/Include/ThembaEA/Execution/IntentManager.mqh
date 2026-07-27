//+------------------------------------------------------------------+
//| IntentManager.mqh                                                 |
//| Themba Adaptive Intraday Engine — Execution                       |
//|                                                                    |
//| TASK-034 — durable-intent / idempotency persistence, per             |
//| TASK-002_PHASE2_SPECIFICATION.md section 12: before submitting an       |
//| order, persist an intent record (symbol, direction, size, timestamp)      |
//| that survives a crash/restart between "about to submit" and "confirmed      |
//| filled or confirmed rejected." On restart, an orphaned intent record is       |
//| reconciled against actual open positions before resuming normal               |
//| operation — this is what prevents a crash-and-restart from causing a           |
//| second, duplicate order for the same signal.                                     |
//|                                                                    |
//| Storage: instance-scoped (account+server+symbol+magic) native MQL5      |
//| global variables, same double-only mechanism as StateManager.mqh/          |
//| CooldownManager.mqh. The 'active' flag is set via                            |
//| GlobalVariableSetOnCondition (compare-and-set) so IM_BeginIntent itself        |
//| is the same-tick idempotency guard: a second call while an intent is           |
//| already active fails closed (returns false, no second order should be           |
//| submitted) rather than silently overwriting the first intent.                     |
//|                                                                    |
//| Reconciliation policy (IM_ReconcileOnRestart): if an intent record is    |
//| found active at OnInit, check whether a position matching symbol+magic     |
//| now exists. Either way — found (the order filled before the crash) or       |
//| not found (it was rejected, or the crash happened before the order even       |
//| reached the broker) — the intent is cleared once reconciled, since the         |
//| live position list is now the ground truth and the whole point of              |
//| reconciliation is to resume normal operation with an accurate picture of         |
//| what is actually open, not to leave the symbol permanently blocked.                |
//+------------------------------------------------------------------+
#property strict

string IM_InstanceNamespace(const string symbol, const long magic)
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   return "ThembaEA_IM_" + IntegerToString(login) + "_" + server + "_" + symbol + "_" +
          IntegerToString(magic);
  }

string IM_Key(const string symbol, const long magic, const string field)
  {
   return IM_InstanceNamespace(symbol, magic) + "__" + field;
  }

double IM_GetDouble(const string symbol, const long magic, const string field,
                     const double default_value)
  {
   string key = IM_Key(symbol, magic, field);
   if(!GlobalVariableCheck(key))
      return default_value;
   return GlobalVariableGet(key);
  }

void IM_SetDouble(const string symbol, const long magic, const string field, const double value)
  {
   GlobalVariableSet(IM_Key(symbol, magic, field), value);
  }

//+------------------------------------------------------------------+
//| True iff an intent is currently recorded active for 'symbol'+'magic'.  |
//+------------------------------------------------------------------+
bool IM_HasActiveIntent(const string symbol, const long magic)
  {
   return IM_GetDouble(symbol, magic, "active", 0.0) != 0.0;
  }

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding    |
//| 1):** the bootstrap "create the lock variable if absent" step must         |
//| run exactly once, from OnInit, BEFORE any order-submission logic ever         |
//| runs — never from inside IM_BeginIntent itself (the hot path). The           |
//| original code re-ran "if(!GlobalVariableCheck(active_key))                     |
//| GlobalVariableSet(active_key, 0.0)" on every call: if a second instance             |
//| sharing this symbol+magic ever raced the FIRST-EVER creation of this                 |
//| key (both see it absent before either creates it), one instance's                      |
//| unconditional GlobalVariableSet(0.0) could silently reset the OTHER                      |
//| instance's already-successful CAS-to-1.0 back to 0.0, breaking the                         |
//| idempotency guard entirely. Native MQL5 GlobalVariables have no atomic                       |
//| create-if-absent primitive, so this bootstrap cannot be made airtight                          |
//| purely with GlobalVariable calls in the general multi-instance case --                           |
//| calling this ONCE from OnInit (a point that, per this project's own                                |
//| one-instance-per-symbol+magic convention used throughout TASK-034/041,                              |
//| is not itself expected to race against another instance's OnInit for                                  |
//| the SAME symbol+magic) closes the practical exposure: after OnInit, the                                 |
//| key always already exists, so IM_BeginIntent's own CAS never takes the                                    |
//| create-if-absent branch again.                                                                               |
//+------------------------------------------------------------------+
void IM_EnsureInitialized(const string symbol, const long magic)
  {
   string active_key = IM_Key(symbol, magic, "active");
   if(!GlobalVariableCheck(active_key))
      GlobalVariableSet(active_key, 0.0);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 5):** builds the broker-visible intent ID from a persisted microsecond        |
//| counter -- native MQL5 global variables are double-only (no string             |
//| storage), so the ID itself is never persisted as a string; it is                 |
//| DETERMINISTICALLY RECONSTRUCTED from the persisted numeric component                |
//| whenever needed (IM_GetIntentId). GetMicrosecondCount() (microseconds               |
//| since this terminal's own start) exactly round-trips through a double for              |
//| any realistic terminal uptime (double exactly represents every integer up                 |
//| to 2^53 -- roughly 285 years of microseconds -- the same round-trip                          |
//| argument this project already applies to ulong deal tickets stored as                           |
//| doubles, see DailyWeeklyLimits.mqh's own cash-flow cursor). Uniqueness                              |
//| only needs to hold within this symbol+magic's own history, which a                                    |
//| microsecond-resolution counter satisfies per this codebase's existing                                    |
//| BuildSignalId precedent.                                                                                    |
//+------------------------------------------------------------------+
string IM_BuildIntentId(const double intent_micro)
  {
   return StringFormat("TI%.0f", intent_micro);
  }

//+------------------------------------------------------------------+
//| Reconstructs the current intent's broker-visible ID from its persisted    |
//| microsecond component. "TI0" (micro==0, the field's default) means NO         |
//| intent ID was ever recorded for this symbol+magic — callers must treat            |
//| that as "cannot be searched for in history", never as a real ID.                     |
//+------------------------------------------------------------------+
string IM_GetIntentId(const string symbol, const long magic)
  {
   return IM_BuildIntentId(IM_GetDouble(symbol, magic, "intent_micro", 0.0));
  }

//+------------------------------------------------------------------+
//| Begins a new intent record just before order submission. Returns      |
//| false (and records nothing) if an intent is already active — this is    |
//| the idempotency guard: a caller must never submit a second order for      |
//| the same symbol+magic while one is already in flight. 'is_long' is         |
//| stored as 1.0/0.0, 'volume' and 'timestamp' verbatim.                        |
//|                                                                    |
//| **Assumes IM_EnsureInitialized(symbol, magic) has already run this       |
//| instance's lifetime (the live EA calls it once from OnInit) — this          |
//| function itself no longer performs the racy create-if-absent bootstrap.**    |
//|                                                                    |
//| **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding      |
//| 5):** now also generates and persists a unique intent_id and returns it        |
//| via 'intent_id_out' — the caller MUST tag the order's own broker comment              |
//| with this exact ID before submitting, per section 11's "broker-visible                   |
//| correlation" requirement (resolves round 3's "not crash-safe, no unique                     |
//| correlation across history" finding). Previously this record had no ID at                       |
//| all, so a crash/restart could never distinguish "this specific intent's                             |
//| own order" from any other order sharing the same symbol+magic in closed                                 |
//| history.**                                                                                                  |
//+------------------------------------------------------------------+
bool IM_BeginIntent(const string symbol, const long magic, const bool is_long,
                     const double volume, const datetime now, string &intent_id_out)
  {
   intent_id_out = "";
   string active_key = IM_Key(symbol, magic, "active");
   // Deliberately does NOT call IM_EnsureInitialized here — re-running the
   // create-if-absent check on every hot-path call would reintroduce
   // exactly the race this fix removes. If the key genuinely does not
   // exist yet (IM_EnsureInitialized was never called), this call fails
   // closed (GlobalVariableSetOnCondition returns false against a
   // nonexistent variable) rather than silently racing to create it.
   if(!GlobalVariableSetOnCondition(active_key, 1.0, 0.0))
      return false; // an intent is already active — refuse a second one

   double intent_micro = (double)GetMicrosecondCount();
   IM_SetDouble(symbol, magic, "is_long", is_long ? 1.0 : 0.0);
   IM_SetDouble(symbol, magic, "volume", volume);
   IM_SetDouble(symbol, magic, "timestamp", (double)now);
   IM_SetDouble(symbol, magic, "intent_micro", intent_micro);
   intent_id_out = IM_BuildIntentId(intent_micro);
   return true;
  }

//+------------------------------------------------------------------+
//| Clears the intent record — call on confirmed fill OR confirmed          |
//| rejection (both are a definitive outcome; only a crash mid-flight         |
//| leaves 'active' stuck at 1.0 for IM_ReconcileOnRestart to resolve).          |
//+------------------------------------------------------------------+
void IM_ClearIntent(const string symbol, const long magic)
  {
   IM_SetDouble(symbol, magic, "active", 0.0);
  }

//+------------------------------------------------------------------+
//| True iff a position matching 'symbol'+'magic' currently exists —       |
//| used by reconciliation to determine whether an orphaned intent            |
//| actually filled before the crash.                                            |
//+------------------------------------------------------------------+
bool IM_HasMatchingPosition(const string symbol, const long magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| True iff an ACTIVE (not-yet-terminal) order matching 'symbol'+'magic'  |
//| currently exists at the broker — added, 2026-07-22 (Codex review          |
//| finding, seventh round, P0 finding 1): a restart must not silently           |
//| clear the durable intent and resume normal operation while an accepted        |
//| order the crash interrupted could still fill later; only a genuinely            |
//| terminal state (a matching position exists, or neither a position NOR             |
//| a pending order exists) is safe to treat as reconciled.                              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 5):** now also returns the matching order's own ticket, so a caller can           |
//| reconstruct AsyncFillCorrelator.mqh's session-only pending-order array               |
//| after a restart (see IM_ReconcileOnRestart's own header for why this is                 |
//| required — otherwise a still-pending order left active by a restart can                    |
//| never be resolved by OnTradeTransaction's normal AFC_FindPending path,                         |
//| leaving the intent permanently stuck until another restart).                                       |
//+------------------------------------------------------------------+
bool IM_FindMatchingPendingOrder(const string symbol, const long magic, ulong &ticket_out)
  {
   ticket_out = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      ticket_out = ticket;
      return true;
     }
   return false;
  }

bool IM_HasMatchingPendingOrder(const string symbol, const long magic)
  {
   ulong ignore;
   return IM_FindMatchingPendingOrder(symbol, magic, ignore);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 5):** searches CLOSED order history for an order whose own comment          |
//| matches 'intent_id' — per section 11: "an order filled and closed before        |
//| restart is correctly found in history, not misclassified as abandoned."             |
//| Previously nothing searched history at all, so "a fill that also closes             |
//| before restart has no live position/order trace" was cleared as if the                  |
//| order had never been submitted, losing the correlation entirely. Scans a                    |
//| bounded window (matching DailyWeeklyLimits.mqh's own DWL_                                        |
//| ApplyCashFlowAdjustments bounded-HistorySelect convention, not an                                    |
//| unbounded full-history scan) from just before the intent's own recorded                                 |
//| timestamp to just after now.                                                                                |
//+------------------------------------------------------------------+
bool IM_FindIntentInHistory(const string symbol, const long magic, const string intent_id,
                             const datetime since, bool &was_filled_out)
  {
   was_filled_out = false;
   if(intent_id == "" || intent_id == "TI0")
      return false; // no real intent ID was ever recorded — nothing to search for

   datetime from = (since > 0 ? since : TimeCurrent()) - 60;
   datetime to   = TimeCurrent() + 60;
   if(!HistorySelect(from, to))
      return false;

   int total = HistoryOrdersTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryOrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryOrderGetInteger(ticket, ORDER_MAGIC) != magic)
         continue;
      if(HistoryOrderGetString(ticket, ORDER_SYMBOL) != symbol)
         continue;
      if(HistoryOrderGetString(ticket, ORDER_COMMENT) != intent_id)
         continue;

      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
      was_filled_out = (state == ORDER_STATE_FILLED);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Call at OnInit (restart reconciliation) and, while an intent remains       |
//| unresolved by the normal live paths, again from OnTick — see the EA's         |
//| own OnInit/OnTick comments for why a single OnInit call is not always            |
//| sufficient. If an intent record is active, reconciles it against, in            |
//| order: the live position list, the live pending-order list, closed order            |
//| history (by broker-visible intent-ID comment match), and finally the                  |
//| InpIntentTimeoutSeconds abandonment timeout.                                              |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, seventh round, P0 finding 1):        |
//| a matching position existing means the order filled (safe to clear); a               |
//| matching PENDING ORDER (no position yet) means the submission is still                    |
//| live at the broker -- the intent MUST stay active so IM_BeginIntent's own                     |
//| CAS continues to refuse a duplicate submission until OnTradeTransaction                            |
//| observes the order's actual terminal outcome.**                                                       |
//|                                                                    |
//| **Extended, 2026-07-22 (Codex review finding, eighth round, P0 finding      |
//| 5):** previously, "neither a position nor a pending order exists" was              |
//| treated as "never submitted" unconditionally -- but an order that filled                 |
//| AND closed entirely before this restart leaves NEITHER trace, and was                        |
//| being silently misclassified as abandoned. Now searches closed order                             |
//| history for the intent's own broker-visible ID before concluding                                     |
//| anything, and only treats a truly untraceable intent as abandoned once it                               |
//| has aged past InpIntentTimeoutSeconds (default 30) -- a very recent                                          |
//| intent with no trace anywhere yet is left active (still_pending_out=true,                                       |
//| pending_order_ticket_out=0) for the caller to retry on a later tick,                                                |
//| rather than assumed abandoned before the broker has even had a chance to                                             |
//| respond. 'pending_order_ticket_out' is set (nonzero) only in the live-                                                    |
//| pending-order case, letting the caller reconstruct                                                                          |
//| AsyncFillCorrelator.mqh's session-only pending array -- without this, a                                                          |
//| still-pending order surviving a restart could never be resolved by the                                                              |
//| normal OnTradeTransaction/AFC_FindPending path (that array is session-only,                                                              |
//| empty after every restart), leaving the intent stuck until yet another                                                                      |
//| restart. 'abandoned_out' is set true only on the genuine timeout path, so                                                                      |
//| the caller can log it distinctly from an ordinary "never reached the                                                                              |
//| broker" same-tick clear.**                                                                                                                            |
//+------------------------------------------------------------------+
bool IM_ReconcileOnRestart(const string symbol, const long magic, const int timeout_seconds,
                            bool &was_filled_out, bool &still_pending_out,
                            ulong &pending_order_ticket_out, bool &abandoned_out)
  {
   was_filled_out = false;
   still_pending_out = false;
   pending_order_ticket_out = 0;
   abandoned_out = false;
   if(!IM_HasActiveIntent(symbol, magic))
      return false;

   if(IM_HasMatchingPosition(symbol, magic))
     {
      was_filled_out = true;
      IM_ClearIntent(symbol, magic);
      return true;
     }

   ulong pending_ticket;
   if(IM_FindMatchingPendingOrder(symbol, magic, pending_ticket))
     {
      still_pending_out = true;
      pending_order_ticket_out = pending_ticket;
      return true; // intent deliberately left ACTIVE -- see header comment
     }

   datetime intent_time = (datetime)IM_GetDouble(symbol, magic, "timestamp", 0.0);
   string   intent_id   = IM_GetIntentId(symbol, magic);
   bool     history_filled;
   if(IM_FindIntentInHistory(symbol, magic, intent_id, intent_time, history_filled))
     {
      // Found in closed history — definitively terminal either way (filled
      // then closed, or resolved cancelled/rejected before this restart).
      was_filled_out = history_filled;
      IM_ClearIntent(symbol, magic);
      return true;
     }

   int age_seconds = (intent_time == 0) ? timeout_seconds : (int)(TimeCurrent() - intent_time);
   if(age_seconds >= timeout_seconds)
     {
      abandoned_out = true;
      IM_ClearIntent(symbol, magic);
      return true;
     }

   // No trace anywhere yet, but still younger than the abandonment timeout
   // -- the broker may simply not have responded yet. Leave active; the
   // caller retries this same reconciliation on a later tick.
   still_pending_out = true;
   return true;
  }

//+------------------------------------------------------------------+
//| Test-only: wipes every field for 'symbol'+'magic' so a test run        |
//| leaves no residue. Never called by normal EA logic.                       |
//+------------------------------------------------------------------+
void IM_ResetInstance(const string symbol, const long magic)
  {
   IM_SetDouble(symbol, magic, "active", 0.0);
   IM_SetDouble(symbol, magic, "is_long", 0.0);
   IM_SetDouble(symbol, magic, "volume", 0.0);
   IM_SetDouble(symbol, magic, "timestamp", 0.0);
   IM_SetDouble(symbol, magic, "intent_micro", 0.0);
  }
