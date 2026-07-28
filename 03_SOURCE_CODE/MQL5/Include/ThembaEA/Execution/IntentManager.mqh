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

#include "../Core/KeyEncoding.mqh"

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** previously concatenated the raw, unbounded server name AND               |
//| symbol name directly into the key — an ordinary Deriv synthetic symbol           |
//| name ("Volatility 100 Index") combined with a realistic server name                 |
//| already exceeds MT5's 63-character global-variable name limit, so                       |
//| GlobalVariableSet silently failed and order submission broke permanently                    |
//| on exactly the symbols this project trades most. Now delegates to                               |
//| KeyEncoding.mqh's KE_InstanceNamespace (fixed-width hash) — see that                                |
//| module's own header.**                                                                                 |
//+------------------------------------------------------------------+
string IM_InstanceNamespace(const string symbol, const long magic)
  {
   return KE_InstanceNamespace("ThembaEA_IM", symbol, magic);
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

//+------------------------------------------------------------------+
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 6):** the write's own success is now returned — every prior caller           |
//| ignored it entirely (the review's own "the code ignores that return           |
//| value" finding). Callers that need fail-closed behavior check this;                 |
//| IM_BeginIntent below is the one that matters most (a failed intent write               |
//| must not be silently treated as a successfully durable one).**                             |
//+------------------------------------------------------------------+
bool IM_SetDouble(const string symbol, const long magic, const string field, const double value)
  {
   return KE_SetDoubleChecked(IM_Key(symbol, magic, field), value);
  }

//+------------------------------------------------------------------+
//| True iff an intent is currently recorded active for 'symbol'+'magic'.  |
//+------------------------------------------------------------------+
bool IM_HasActiveIntent(const string symbol, const long magic)
  {
   return IM_GetDouble(symbol, magic, "active", 0.0) != 0.0;
  }

//+------------------------------------------------------------------+
//| **Superseded, 2026-07-27 (Codex review finding, ninth round, P0     |
//| finding 3): this OnInit-only bootstrap is no longer called or       |
//| needed.** The previous "one instance per symbol+magic never races    |
//| its own OnInit" assumption this relied on is exactly what the review |
//| flagged as unproven -- two concurrent OnInit calls (a fast EA        |
//| restart racing a still-shutting-down previous instance, or an        |
//| operator accidentally attaching the same symbol+magic twice) could   |
//| still reset an already-active intent via this exact check-then-set.  |
//| Bootstrap is now folded directly into IM_BeginIntent itself (see      |
//| that function's own header), using the same GetLastError()           |
//| ERR_GLOBALVARIABLE_NOT_FOUND technique StateManager.mqh's own         |
//| SM_AcquireAccountLock fix (round 9, P0 finding 2) already established |
//| -- provably race-free regardless of how many instances race the      |
//| very first-ever call for a given symbol+magic. Kept only as a no-op  |
//| so the EA's own existing OnInit call site does not need to be        |
//| deleted.**                                                            |
//+------------------------------------------------------------------+
void IM_EnsureInitialized(const string symbol, const long magic)
  {
   // Intentionally a no-op -- see header comment above.
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 5):** builds the broker-visible intent ID from a persisted microsecond        |
//| counter -- native MQL5 global variables are double-only (no string             |
//| storage), so the ID itself is never persisted as a string; it is                 |
//| DETERMINISTICALLY RECONSTRUCTED from the persisted numeric component                |
//| whenever needed (IM_GetIntentId).                                                        |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 3):     |
//| this previously used GetMicrosecondCount() ALONE -- microseconds since         |
//| THIS TERMINAL'S OWN START, which resets to a small value on every              |
//| restart. Two intents created shortly after two DIFFERENT terminal               |
//| restarts (a routine, expected event, not a rare edge case) could easily              |
//| collide on this component alone, and IM_FindIntentInHistory searches by                  |
//| exact ID-string match against ORDER_COMMENT -- a collision there could                       |
//| resolve a restart's own orphaned intent against a COMPLETELY UNRELATED                          |
//| historical order from a prior session. Now also folds in 'intent_time'                             |
//| (TimeCurrent() at the moment the intent began -- WALL-CLOCK time, which                            |
//| does NOT reset across a restart, exactly the same fix BuildSignalId                                |
//| already applies for the same reason), so two intents would need to                                |
//| collide on BOTH the exact same wall-clock SECOND and the exact same                                |
//| microsecond-since-terminal-start value to actually collide --                                      |
//| astronomically less likely than either alone.**                                                    |
//+------------------------------------------------------------------+
string IM_BuildIntentId(const datetime intent_time, const double intent_micro)
  {
   return StringFormat("TI%.0f_%.0f", (double)intent_time, intent_micro);
  }

//+------------------------------------------------------------------+
//| Reconstructs the current intent's broker-visible ID from its persisted    |
//| timestamp and microsecond components. "TI0_0" (both fields at their           |
//| defaults) means NO intent ID was ever recorded for this symbol+magic —            |
//| callers must treat that as "cannot be searched for in history", never as             |
//| a real ID.                                                                            |
//+------------------------------------------------------------------+
string IM_GetIntentId(const string symbol, const long magic)
  {
   datetime intent_time = (datetime)IM_GetDouble(symbol, magic, "timestamp", 0.0);
   double   intent_micro = IM_GetDouble(symbol, magic, "intent_micro", 0.0);
   return IM_BuildIntentId(intent_time, intent_micro);
  }

//+------------------------------------------------------------------+
//| Begins a new intent record just before order submission. Returns      |
//| false (and records nothing) if an intent is already active — this is    |
//| the idempotency guard: a caller must never submit a second order for      |
//| the same symbol+magic while one is already in flight. 'is_long' is         |
//| stored as 1.0/0.0, 'volume' and 'timestamp' verbatim.                        |
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
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 3):     |
//| the bootstrap ("create the 'active' key if this is the very first call        |
//| ever for this symbol+magic") is now folded directly into THIS function's       |
//| own atomic acquire, exactly like StateManager.mqh's SM_AcquireAccountLock          |
//| fix (round 9, P0 finding 2).**                                                       |
//|                                                                    |
//| **Fixed again, 2026-07-28 (Codex review finding, tenth round, P0 finding  |
//| 4): the round-9 fix above still bootstrapped via an UNCONDITIONAL             |
//| GlobalVariableSet(active_key, 0.0) -- a blind overwrite, not a create-if-        |
//| absent, exactly the same destructive race StateManager.mqh's own              |
//| SM_AcquireAccountLock had (round-10 P0 finding 1, see that function's              |
//| header for the full counterexample). A second, merely-delayed caller               |
//| reaching that same line AFTER a first caller had already raced through                 |
//| bootstrap-then-CAS and legitimately begun an intent (active_key == 1.0)                    |
//| would stomp it back to 0.0, letting a SECOND caller also begin an intent                        |
//| for the same symbol+magic -- exactly the duplicate-order risk this                                 |
//| module exists to prevent. Fixed with the same technique as                                             |
//| SM_AcquireAccountLock: on ERR_GLOBALVARIABLE_NOT_FOUND, write a caller-                                     |
//| unique nonzero token directly (never the neutral 0.0 value), then verify                                       |
//| by readback whether this caller's own write survived. IM_HasActiveIntent                                          |
//| only ever tests "!= 0.0" (never "== 1.0" specifically -- confirmed by                                                 |
//| grep across the whole codebase), so a unique nonzero token is a drop-in                                                   |
//| replacement for the bare 1.0 sentinel with no other call site changes                                                        |
//| needed.**                                                                                                                        |
//+------------------------------------------------------------------+
bool IM_BeginIntent(const string symbol, const long magic, const bool is_long,
                     const double volume, const datetime now, string &intent_id_out)
  {
   intent_id_out = "";
   string active_key = IM_Key(symbol, magic, "active");

   bool acquired = false;
   while(true)
     {
      // Caller-unique nonzero claim token -- see header. Only used to make
      // the bootstrap's readback-verify step meaningful; IM_HasActiveIntent
      // and every other reader only ever test "!= 0.0".
      long   now_sec  = (long)TimeCurrent();
      long   tiebreak = ((long)GetMicrosecondCount() + (long)MathRand()) % 1000000L;
      double claim    = (double)(now_sec * 1000000L + tiebreak + 1L);

      ResetLastError();
      if(GlobalVariableSetOnCondition(active_key, claim, 0.0))
        {
         acquired = true;
         break;
        }
      int err = GetLastError();
      if(err == ERR_GLOBALVARIABLE_NOT_FOUND)
        {
         // Race-free first-ever-use bootstrap -- see header. Writes THIS
         // caller's own claim token directly, never the neutral 0.0 value,
         // then verifies by readback whether this caller's own write was
         // the one that actually survived.
         GlobalVariableSet(active_key, claim);
         if(GlobalVariableGet(active_key) == claim)
           {
            acquired = true;
            break;
           }
         continue; // lost the bootstrap race to a concurrent first-time caller
        }
      break; // genuinely already active (CAS failed against a real nonzero value) -- fall through
     }
   if(!acquired)
      return false; // an intent is already active — refuse a second one

   double intent_micro = (double)GetMicrosecondCount();
   // **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding 6):
   // every field write's own success is now checked. If any fails, the
   // 'active' flag (already CAS-set to 1.0 above) is rolled back to 0.0
   // (best-effort) and this returns false -- proceeding to submit a real
   // order whose intent record cannot be durably trusted would defeat the
   // entire crash-recovery mechanism this module exists for.**
   bool all_ok = true;
   all_ok = IM_SetDouble(symbol, magic, "is_long", is_long ? 1.0 : 0.0) && all_ok;
   all_ok = IM_SetDouble(symbol, magic, "volume", volume) && all_ok;
   all_ok = IM_SetDouble(symbol, magic, "timestamp", (double)now) && all_ok;
   all_ok = IM_SetDouble(symbol, magic, "intent_micro", intent_micro) && all_ok;

   if(!all_ok)
     {
      GlobalVariableSet(active_key, 0.0); // best-effort rollback
      PrintFormat("ThembaEA: IntentManager failed to persist intent fields for '%s' magic "
                  "%I64d -- refusing to report a durable intent.", symbol, magic);
      return false;
     }

   // Safety-critical: this record is what a restart's crash-recovery
   // reconciliation depends on entirely (see IM_ReconcileOnRestart) -- per
   // the review's own "no code calls GlobalVariablesFlush... sudden failure
   // can lose unflushed terminal globals" finding, force it to disk now
   // rather than trust MT5's own periodic flush cadence.
   GlobalVariablesFlush();

   intent_id_out = IM_BuildIntentId(now, intent_micro);
   return true;
  }

//+------------------------------------------------------------------+
//| Clears the intent record — call on confirmed fill OR confirmed          |
//| rejection (both are a definitive outcome; only a crash mid-flight         |
//| leaves 'active' stuck at 1.0 for IM_ReconcileOnRestart to resolve).          |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 3):     |
//| this previously discarded the write's own success and never flushed --        |
//| a silent failure here leaves 'active' still 1.0 on disk even though          |
//| this instance believes the intent is resolved, so a later restart would          |
//| find a STALE active record for an intent that has genuinely already            |
//| concluded (a false, unnecessary reconciliation, not a duplicate-order              |
//| risk, but still worth surfacing rather than silently swallowing). Now                |
//| returns the write's own success and flushes on a successful clear,                      |
//| matching every other safety-critical write in this module.**                                |
//+------------------------------------------------------------------+
bool IM_ClearIntent(const string symbol, const long magic)
  {
   bool ok = IM_SetDouble(symbol, magic, "active", 0.0);
   if(ok)
      GlobalVariablesFlush();
   else
      PrintFormat("ThembaEA: IntentManager failed to persist intent clear for '%s' magic "
                  "%I64d -- a restart before this succeeds would see a stale active record.",
                  symbol, magic);
   return ok;
  }

//+------------------------------------------------------------------+
//| True iff a position matching 'symbol'+'magic'+'intent_id' currently   |
//| exists — used by reconciliation to determine whether an orphaned      |
//| intent actually filled before the crash.                              |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding    |
//| 3): this previously matched on symbol+magic ALONE -- an UNRELATED       |
//| position sharing this same symbol+magic (a manual position, a leftover      |
//| from a DIFFERENT, already-resolved intent this instance never fully          |
//| cleaned up, or in principle a second concurrent intent this module's           |
//| own idempotency guard should prevent but a caller bug could still                |
//| create) would be silently treated as proof THIS intent filled. Now                  |
//| additionally requires POSITION_COMMENT to match the exact intent_id                     |
//| this intent's own order was tagged with at submission (see                              |
//| IM_BeginIntent's own header) -- MT5 positions typically inherit their                    |
//| comment from the opening deal/order, but even where a broker's own                       |
//| comment-propagation behavior is unreliable, a false negative here is                     |
//| SAFE (not a duplicate-order risk): the caller simply falls through to                     |
//| IM_FindIntentInHistory below, which also now matches by this same ID                      |
//| against order AND deal history.**                                                         |
//+------------------------------------------------------------------+
bool IM_HasMatchingPosition(const string symbol, const long magic, const string intent_id)
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
      if(intent_id != "" && PositionGetString(POSITION_COMMENT) != intent_id)
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
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 3):     |
//| same fix as IM_HasMatchingPosition above -- now additionally requires         |
//| ORDER_COMMENT to match the exact intent_id, so an unrelated pending           |
//| order sharing this symbol+magic cannot be mistaken for THIS intent's           |
//| own still-live submission.**                                                     |
//+------------------------------------------------------------------+
bool IM_FindMatchingPendingOrder(const string symbol, const long magic, const string intent_id,
                                   ulong &ticket_out)
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
      if(intent_id != "" && OrderGetString(ORDER_COMMENT) != intent_id)
         continue;
      ticket_out = ticket;
      return true;
     }
   return false;
  }

bool IM_HasMatchingPendingOrder(const string symbol, const long magic, const string intent_id)
  {
   ulong ignore;
   return IM_FindMatchingPendingOrder(symbol, magic, intent_id, ignore);
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
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 3),    |
//| three defects:**                                                                 |
//| 1. **HistorySelect failure was indistinguishable from a successful          |
//|    search that found nothing** -- both returned `false`, and                    |
//|    IM_ReconcileOnRestart's own timeout logic then converted that same             |
//|    `false` into "abandoned" once InpIntentTimeoutSeconds elapsed,                     |
//|    turning a TEMPORARY history-lookup failure into permission for a                       |
//|    duplicate submission. `lookup_failed_out` now distinguishes the two:                       |
//|    true means "genuinely unknown, try again later", never counted                                 |
//|    toward abandonment; false + a `false` return means "verified absent                               |
//|    in both order and deal history within this window".                                                   |
//| 2. **Only order history was searched, never deal history** -- a fill        |
//|    whose own order fell outside this bounded window's order-history         |
//|    retention (broker-dependent) but whose DEAL is still retrievable was      |
//|    missed entirely. Now falls back to a direct deal-history search by       |
//|    symbol+magic+DEAL_COMMENT if no matching order is found.                  |
//| 3. **`was_filled_out` was true only for final state ORDER_STATE_FILLED**     |
//|    -- an order that PARTIALLY filled and was then cancelled (real            |
//|    exposure was created, but the order's own final state is CANCELED,        |
//|    not FILLED) was misclassified as "never filled". Now also checks          |
//|    deal history for ANY DEAL_ENTRY_IN deal tied to the matched order's       |
//|    own ticket -- a real partial fill leaves exactly such a deal even         |
//|    when the order's final state says otherwise.                             |
//+------------------------------------------------------------------+
bool IM_FindIntentInHistory(const string symbol, const long magic, const string intent_id,
                             const datetime since, bool &was_filled_out, bool &lookup_failed_out)
  {
   was_filled_out = false;
   lookup_failed_out = false;
   if(intent_id == "" || intent_id == "TI0_0")
      return false; // no real intent ID was ever recorded — nothing to search for

   datetime from = (since > 0 ? since : TimeCurrent()) - 60;
   datetime to   = TimeCurrent() + 60;
   if(!HistorySelect(from, to))
     {
      lookup_failed_out = true; // genuinely unknown -- NOT "verified absent"
      return false;
     }

   int total_orders = HistoryOrdersTotal();
   for(int i = 0; i < total_orders; i++)
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
      if(!was_filled_out)
        {
         // A partial-then-cancelled order's own final state is not FILLED,
         // but a real fill still leaves a DEAL_ENTRY_IN deal tied to this
         // exact order ticket -- check for that definitive evidence too.
         int total_deals = HistoryDealsTotal();
         for(int d = 0; d < total_deals; d++)
           {
            ulong deal_ticket = HistoryDealGetTicket(d);
            if(deal_ticket == 0)
               continue;
            if(HistoryDealGetInteger(deal_ticket, DEAL_ORDER) != ticket)
               continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
              {
               was_filled_out = true;
               break;
              }
           }
        }
      return true;
     }

   // Fallback: no matching ORDER found in this window -- search DEAL
   // history directly by comment (see fix note 2 above).
   int total_deals = HistoryDealsTotal();
   for(int d = 0; d < total_deals; d++)
     {
      ulong deal_ticket = HistoryDealGetTicket(d);
      if(deal_ticket == 0)
         continue;
      if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != magic)
         continue;
      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != symbol)
         continue;
      if(HistoryDealGetString(deal_ticket, DEAL_COMMENT) != intent_id)
         continue;

      was_filled_out = ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) ==
                         DEAL_ENTRY_IN);
      return true;
     }

   return false; // verified absent in both order and deal history within this window
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
//| still-pending order surviving a restart could never be resolved by the      |
//| normal OnTradeTransaction/AFC_FindPending path (that array is session-only,  |
//| empty after every restart), leaving the intent stuck until yet another      |
//| restart. 'abandoned_out' is set true only on the genuine timeout path, so   |
//| the caller can log it distinctly from an ordinary "never reached the        |
//| broker" same-tick clear.**                                                   |
//|                                                                    |
//| **Fixed, 2026-07-27 (Codex review finding, ninth round, P0 finding 3):     |
//| position/pending-order matching now requires this exact intent_id (see        |
//| IM_HasMatchingPosition/IM_FindMatchingPendingOrder's own headers). A            |
//| genuine HistorySelect failure inside IM_FindIntentInHistory no longer                 |
//| falls through to the abandonment timeout as if it were a verified-absent               |
//| result -- 'lookup_failed_out' is checked explicitly, and a failed lookup                    |
//| leaves the intent ACTIVE for a later retry (still_pending_out=true)          |
//| regardless of age, exactly like the "broker hasn't responded yet" case,      |
//| never counting a temporary lookup failure toward abandonment.**              |
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

   string intent_id = IM_GetIntentId(symbol, magic);

   if(IM_HasMatchingPosition(symbol, magic, intent_id))
     {
      was_filled_out = true;
      IM_ClearIntent(symbol, magic);
      return true;
     }

   ulong pending_ticket;
   if(IM_FindMatchingPendingOrder(symbol, magic, intent_id, pending_ticket))
     {
      still_pending_out = true;
      pending_order_ticket_out = pending_ticket;
      return true; // intent deliberately left ACTIVE -- see header comment
     }

   datetime intent_time = (datetime)IM_GetDouble(symbol, magic, "timestamp", 0.0);
   bool     history_filled;
   bool     history_lookup_failed;
   if(IM_FindIntentInHistory(symbol, magic, intent_id, intent_time, history_filled,
                              history_lookup_failed))
     {
      // Found in closed history — definitively terminal either way (filled
      // then closed, or resolved cancelled/rejected before this restart).
      was_filled_out = history_filled;
      IM_ClearIntent(symbol, magic);
      return true;
     }

   if(history_lookup_failed)
     {
      // Genuinely unknown -- HistorySelect itself failed, not "searched and
      // found nothing". Must never count toward abandonment; retried on a
      // later tick exactly like an unresponded-to broker submission.
      still_pending_out = true;
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
