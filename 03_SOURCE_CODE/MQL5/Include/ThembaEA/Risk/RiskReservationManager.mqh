//+------------------------------------------------------------------+
//| RiskReservationManager.mqh                                        |
//| Themba Adaptive Intraday Engine — Risk                            |
//|                                                                    |
//| **Added, 2026-07-27 (Codex review finding, ninth round, P0 finding    |
//| 1):** closes the cross-symbol total-open-risk race the review           |
//| reported: `ComputeOwnMagicOpenRiskCash()` (ThembaAdaptiveIntradayEA.mq5)      |
//| only sees REAL positions/pending orders. Two chart instances sharing            |
//| the same magic number on DIFFERENT symbols could each independently                 |
//| take that same snapshot, each see headroom under the 1% total-open-risk                 |
//| cap for their OWN proposed trade, and both submit -- since neither saw                      |
//| the OTHER's in-flight (not-yet-real) submission, their combined risk                            |
//| can exceed the cap even though each one individually passed its own                                check.
//|                                                                    |
//| Fix: a persisted, per-symbol "reservation" record, keyed under a          |
//| MAGIC-WIDE (not per-symbol) namespace so every symbol this magic              |
//| manages can be summed together (KeyEncoding.mqh's KE_MagicNamespace).             |
//| Checking existing exposure, summing live reservations, and writing a                 |
//| NEW reservation all happen under StateManager.mqh's own account-wide                     |
//| lock (StateManager.mqh's finding-2 fix: owner-token compare-and-set,                         |
//| no ABA release race) as ONE critical section -- this is the account/                             |
//| magic-wide reservation the review's own required correction asks for.                                |
//|                                                                    |
//| **Redesigned, 2026-07-28 (Codex review finding, tenth round, P0        |
//| finding 2):** the round-9 design above had three real gaps this closes:  |
//|                                                                    |
//| 1. **Ownerless reservation key.** RRM_Key(symbol, magic) was ONE shared    |
//|    key per symbol+magic -- a second caller for the SAME symbol+magic          |
//|    (e.g. a rejected cross-check retried on the next bar while a PRIOR             |
//|    caller's own reservation was still live for a different reason)               |
//|    would silently overwrite/delete the first caller's own live                       |
//|    reservation. Fixed: every RRM_TryReserve call now mints its OWN                       |
//|    structurally-unique key (RRM_NewReservationKey) and returns it via                        |
//|    'reservation_key_out' -- the caller must retain and pass that EXACT                          |
//|    key to RRM_ReleaseReservation. Because no two attempts can ever share                            |
//|    a key, release is now inherently owner-checked: a caller can only                                    |
//|    ever affect the ONE reservation it was itself given the key to, never                                    |
//|    another caller's.                                                                                            |
//| 2. **Non-atomic exposure check.** ComputeOwnMagicOpenRiskCash()'s own          |
//|    actual-position/pending-order snapshot was taken in the EA BEFORE               |
//|    RRM_TryReserve's own lock acquisition -- so "actual exposure +                        |
//|    reservations + new reservation" was never genuinely one critical                          |
//|    section; a position could appear between the snapshot and the locked                          |
//|    decision. Fixed: RRM_TryReserveLocked (below) now assumes the                                     |
//|    account lock is ALREADY held by the caller, so the EA can acquire the                                 |
//|    lock, take the actual-exposure snapshot, and call this function --                                        |
//|    all under ONE hold. RRM_TryReserve (unchanged signature) remains as a                                         |
//|    convenience wrapper for callers that do not need to enclose their own                                             |
//|    exposure snapshot in the same critical section.                                                                       |
//| 3. **Unconditional time-based aging-out.** The sum used to silently             |
//|    exclude any reservation older than RRM_STALE_SECONDS (120s) -- an                    |
//|    accepted-but-not-yet-broker-confirmed request slower than that would                     |
//|    simply vanish from the cap check, understating real risk. Fixed:                             |
//|    RRM_SumLiveReservationsLocked now counts EVERY reservation currently                             |
//|    present, unconditionally -- a reservation is removed from the sum                                    |
//|    only by an explicit RRM_ReleaseReservation call (normal resolution)                                      |
//|    or a caller-driven reconciliation pass that has independently proven                                         |
//|    the underlying intent's terminal disposition (see                                                                |
//|    RRM_FindAgedReservations below, the caller-driven investigation                                                      |
//|    entry point this replaces automatic exclusion with).                                                                 |
//+------------------------------------------------------------------+
#property strict

#include "../Core/StateManager.mqh"

#define RRM_STALE_SECONDS 120

//+------------------------------------------------------------------+
//| Magic-wide namespace prefix every symbol's own reservation key for   |
//| this magic shares -- see KE_MagicNamespace's own header for why this   |
//| (not KE_InstanceNamespace) is required for prefix-scanning.           |
//+------------------------------------------------------------------+
string RRM_Prefix(const long magic)
  {
   return KE_MagicNamespace("ThembaEA_RRM", magic);
  }

//+------------------------------------------------------------------+
//| Shared key-prefix for every reservation ATTEMPT on this symbol+magic  |
//| -- NOT a reservation key by itself (round-10 P0 finding 2: a           |
//| reservation key is now unique PER ATTEMPT, not per symbol+magic; see    |
//| RRM_NewReservationKey below).                                            |
//+------------------------------------------------------------------+
string RRM_SymbolPrefix(const string symbol, const long magic)
  {
   return RRM_Prefix(magic) + "__" + KE_HashHex(symbol);
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex round-10 P0 finding 2):** mints a           |
//| structurally-unique key for ONE reservation attempt on this               |
//| symbol+magic -- see file header point 1 for why uniqueness per attempt      |
//| (not per symbol+magic) is what makes release owner-checked. The 6-hex-        |
//| digit suffix is a truncated mix of the microsecond counter, a random           |
//| component, and the current second -- collision resistance only needs             |
//| to cover the small number of reservations ANY ONE symbol+magic ever                 |
//| plausibly holds concurrently (in practice 0 or 1, rarely more), not a                   |
//| global uniqueness guarantee; kept short so the full key plus its own                       |
//| "__since" companion (+7 chars) stays safely under MT5's 63-character                          |
//| global-variable name limit alongside RRM_SymbolPrefix's own 47                                   |
//| characters (29 from KE_MagicNamespace + 18 from the "__"+16-hex symbol                              |
//| hash).                                                                                                |
//+------------------------------------------------------------------+
string RRM_NewReservationKey(const string symbol, const long magic)
  {
   uint mix = (uint)GetMicrosecondCount() ^ ((uint)MathRand() << 16) ^ (uint)TimeCurrent();
   return RRM_SymbolPrefix(symbol, magic) + "_" + StringFormat("%06X", mix & 0xFFFFFF);
  }

//+------------------------------------------------------------------+
//| Internal: sums every reservation currently held under this magic's    |
//| own namespace, across every symbol and every in-flight attempt --      |
//| enumerates every terminal-wide global variable (GlobalVariablesTotal()/ |
//| GlobalVariableName(i), the only MQL5 primitive that can discover        |
//| "every key matching a prefix"; safe against unrelated globals since     |
//| the prefix itself is a collision-resistant hash of login+server+magic). |
//| MUST be called with the account lock already held by the caller.        |
//|                                                                    |
//| **Changed, 2026-07-28 (Codex round-10 P0 finding 2):** no longer         |
//| excludes reservations by elapsed age -- see file header point 3. Every       |
//| reservation currently present counts, unconditionally.                          |
//+------------------------------------------------------------------+
double RRM_SumLiveReservationsLocked(const long magic)
  {
   string prefix = RRM_Prefix(magic);
   double sum = 0.0;
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0)
         continue; // does not start with this magic's own reservation prefix
      if(StringLen(name) > 7 && StringSubstr(name, StringLen(name) - 7) == "__since")
         continue; // the timestamp companion key, not a reservation value itself

      sum += GlobalVariableGet(name);
     }
   return sum;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex round-10 P0 finding 2):** enumerates every  |
//| reservation currently held under this magic's namespace whose own       |
//| "__since" timestamp is older than 'age_threshold_seconds', for a         |
//| CALLER-DRIVEN reconciliation pass (e.g. at EA restart) -- this NEVER      |
//| removes anything from the cap sum by itself (see file header point 3);      |
//| it only surfaces candidates. The caller must independently confirm the        |
//| underlying intent's terminal disposition against broker history/position       |
//| state (the same pattern IntentManager.mqh's own IM_ReconcileOnRestart          |
//| already establishes) before calling RRM_ReleaseReservation on a returned          |
//| key. Wiring this into the EA's own restart flow is separate, later work            |
//| (round-10 P1 finding 8's async/partial-fill-lifecycle scope) -- not              |
//| attempted here, named honestly rather than silently left unaddressed             |
//| under this finding's own closure. Returns the number of candidate keys              |
//| written into 'keys_out' (capped at ArraySize(keys_out)).                              |
//+------------------------------------------------------------------+
int RRM_FindAgedReservations(const long magic, const int age_threshold_seconds, string &keys_out[])
  {
   int max_out = ArraySize(keys_out);
   string prefix = RRM_Prefix(magic);
   int total = GlobalVariablesTotal();
   int found = 0;
   for(int i = total - 1; i >= 0 && found < max_out; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0)
         continue;
      if(StringLen(name) > 7 && StringSubstr(name, StringLen(name) - 7) == "__since")
         continue;

      string since_key = name + "__since";
      double since = GlobalVariableCheck(since_key) ? GlobalVariableGet(since_key) : 0.0;
      if(since <= 0.0)
         continue; // no timestamp recorded -- nothing to age-check
      if((TimeCurrent() - (datetime)since) < age_threshold_seconds)
         continue;

      keys_out[found] = name;
      found++;
     }
   return found;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-28 (Codex round-10 P0 finding 2):** the guts of        |
//| RRM_TryReserve, ASSUMING the account lock is ALREADY held by the caller. |
//| Lets a caller enclose its own actual-open-risk snapshot (e.g.             |
//| ComputeOwnMagicOpenRiskCash()) in the SAME critical section as the          |
//| reservation sum and write, closing the review's "not one critical           |
//| section" complaint (file header point 2). On success, 'reservation_       |
//| key_out' receives the exact unique key this call wrote -- the caller        |
//| MUST pass that exact key to RRM_ReleaseReservation (never a bare            |
//| symbol+magic release), so a release can never affect a DIFFERENT            |
//| attempt's own live reservation.                                              |
//+------------------------------------------------------------------+
bool RRM_TryReserveLocked(const string symbol, const long magic,
                           const double actual_open_risk_cash, const double proposed_risk_cash,
                           const double risk_cap_percent, const double equity,
                           double &total_projected_percent_out, string &rejection_reason_out,
                           string &reservation_key_out)
  {
   total_projected_percent_out = 0.0;
   rejection_reason_out = "";
   reservation_key_out = "";

   if(equity <= 0.0)
     {
      rejection_reason_out = "risk_reservation_equity_non_positive";
      return false;
     }

   double live_reservations = RRM_SumLiveReservationsLocked(magic);
   double projected_cash = actual_open_risk_cash + live_reservations + proposed_risk_cash;
   double projected_percent = 100.0 * projected_cash / equity;
   total_projected_percent_out = projected_percent;

   if(projected_percent > risk_cap_percent + 1e-6)
     {
      rejection_reason_out = StringFormat(
         "risk_reservation_cap_exceeded_%.4fpct_cap_%.4fpct_others_reserved_%.4f",
         projected_percent, risk_cap_percent, live_reservations);
      return false;
     }

   string key = RRM_NewReservationKey(symbol, magic);
   bool write_ok = KE_SetDoubleChecked(key, proposed_risk_cash);
   write_ok = KE_SetDoubleChecked(key + "__since", (double)TimeCurrent()) && write_ok;

   if(!write_ok)
     {
      // Best-effort cleanup of a partially-written reservation -- this
      // caller's own key, never anyone else's (structurally unique).
      if(GlobalVariableCheck(key))
         GlobalVariableDel(key);
      if(GlobalVariableCheck(key + "__since"))
         GlobalVariableDel(key + "__since");
      rejection_reason_out = "risk_reservation_write_failed";
      return false;
     }

   GlobalVariablesFlush();
   reservation_key_out = key;
   return true;
  }

//+------------------------------------------------------------------+
//| Attempts to reserve 'proposed_risk_cash' for 'symbol'+'magic' against  |
//| 'risk_cap_percent' of 'equity', accounting for BOTH this magic's       |
//| actual current open risk ('actual_open_risk_cash', computed by the     |
//| caller via ComputeOwnMagicOpenRiskCash() -- this module has no          |
//| visibility into that EA-specific scan) AND every OTHER live reservation |
//| under the same magic. The whole check-then-reserve sequence runs under  |
//| ONE account-lock hold, so two concurrent callers (different chart       |
//| instances, same magic) can never both observe the same headroom and     |
//| both reserve into it.                                                   |
//|                                                                    |
//| Convenience wrapper around RRM_TryReserveLocked that acquires/releases  |
//| the account lock itself -- for callers whose own actual-exposure         |
//| snapshot does not need to be enclosed in the same critical section (see  |
//| RRM_TryReserveLocked's own header, and file header point 2, for when a   |
//| caller instead needs to hold the lock across its OWN snapshot too).      |
//|                                                                    |
//| Returns false (no reservation made) if the lock could not be          |
//| acquired, if the projected total would exceed the cap, or if the      |
//| reservation write itself fails -- callers must treat ANY false        |
//| return as "do not submit this order", never as "submit anyway". On    |
//| success, 'reservation_key_out' receives the exact key that MUST be     |
//| passed to RRM_ReleaseReservation (see that function's own header).      |
//+------------------------------------------------------------------+
bool RRM_TryReserve(const string symbol, const long magic, const double actual_open_risk_cash,
                     const double proposed_risk_cash, const double risk_cap_percent,
                     const double equity, double &total_projected_percent_out,
                     string &rejection_reason_out, string &reservation_key_out,
                     const int lock_timeout_ms = 500)
  {
   total_projected_percent_out = 0.0;
   rejection_reason_out = "";
   reservation_key_out = "";

   double owner_token;
   if(!SM_AcquireAccountLock(owner_token, lock_timeout_ms))
     {
      rejection_reason_out = "risk_reservation_lock_timeout";
      return false;
     }

   bool ok = RRM_TryReserveLocked(symbol, magic, actual_open_risk_cash, proposed_risk_cash,
                                    risk_cap_percent, equity, total_projected_percent_out,
                                    rejection_reason_out, reservation_key_out);

   SM_ReleaseAccountLock(owner_token);
   return ok;
  }

//+------------------------------------------------------------------+
//| Releases exactly the reservation identified by 'reservation_key' --   |
//| the EXACT value RRM_TryReserve/RRM_TryReserveLocked returned via       |
//| 'reservation_key_out' on success. Safe to call with an empty string    |
//| (idempotent no-op, e.g. a caller that never successfully reserved).    |
//| Does not require the account lock: this only clears THIS ONE                |
//| structurally-unique key (round-10 P0 finding 2 -- previously a bare          |
//| symbol+magic release could delete a DIFFERENT caller's own live               |
//| reservation sharing that same symbol+magic; a unique-per-attempt key            |
//| makes that impossible, since no other caller was ever given this exact             |
//| key to pass back).                                                                    |
//+------------------------------------------------------------------+
void RRM_ReleaseReservation(const string reservation_key)
  {
   if(reservation_key == "")
      return;
   if(GlobalVariableCheck(reservation_key))
      GlobalVariableDel(reservation_key);
   string since_key = reservation_key + "__since";
   if(GlobalVariableCheck(since_key))
      GlobalVariableDel(since_key);
  }
