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
//| A reservation is short-lived by design: it exists only for the brief          |
//| window between "the pre-submission risk check passed" and "the intent            |
//| this reservation guards has resolved" (filled, rejected, or cancelled),               |
//| at which point the caller releases it explicitly. RRM_STALE_SECONDS is                   |
//| a crash-recovery fallback only (a reservation whose own holder crashed                       |
//| before releasing it must not permanently understate available headroom                          |
//| forever) -- it is deliberately generous relative to a normal order-                                  |
//| submission round-trip, not a tuning knob for normal operation.                                           |
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
//| This symbol+magic's own reservation key.                            |
//+------------------------------------------------------------------+
string RRM_Key(const string symbol, const long magic)
  {
   return RRM_Prefix(magic) + "__" + KE_HashHex(symbol);
  }

//+------------------------------------------------------------------+
//| Internal: sums every LIVE (non-stale) reservation currently held      |
//| under this magic's own namespace, across every symbol -- enumerates   |
//| every terminal-wide global variable (GlobalVariablesTotal()/           |
//| GlobalVariableName(i), the only MQL5 primitive that can discover       |
//| "every key matching a prefix"; safe against unrelated globals since    |
//| the prefix itself is a collision-resistant hash of login+server+magic).|
//| MUST be called with the account lock already held by the caller.       |
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

      string since_key = name + "__since";
      double since = GlobalVariableCheck(since_key) ? GlobalVariableGet(since_key) : 0.0;
      if(since <= 0.0)
         continue; // no timestamp recorded -- treat as inert, not a live reservation
      if((TimeCurrent() - (datetime)since) > RRM_STALE_SECONDS)
         continue; // abandoned (holder crashed without releasing) -- ignore

      sum += GlobalVariableGet(name);
     }
   return sum;
  }

//+------------------------------------------------------------------+
//| Attempts to reserve 'proposed_risk_cash' for 'symbol'+'magic' against  |
//| 'risk_cap_percent' of 'equity', accounting for BOTH this magic's       |
//| actual current open risk ('actual_open_risk_cash', computed by the     |
//| caller via ComputeOwnMagicOpenRiskCash() -- this module has no          |
//| visibility into that EA-specific scan) AND every OTHER symbol's own    |
//| live reservation under the same magic. The whole check-then-reserve   |
//| sequence runs under ONE account-lock hold, so two concurrent callers   |
//| (different chart instances, same magic) can never both observe the    |
//| same headroom and both reserve into it.                                |
//|                                                                    |
//| Returns false (no reservation made) if the lock could not be          |
//| acquired, if the projected total would exceed the cap, or if the      |
//| reservation write itself fails -- callers must treat ANY false        |
//| return as "do not submit this order", never as "submit anyway".       |
//+------------------------------------------------------------------+
bool RRM_TryReserve(const string symbol, const long magic, const double actual_open_risk_cash,
                     const double proposed_risk_cash, const double risk_cap_percent,
                     const double equity, double &total_projected_percent_out,
                     string &rejection_reason_out, const int lock_timeout_ms = 500)
  {
   total_projected_percent_out = 0.0;
   rejection_reason_out = "";

   if(equity <= 0.0)
     {
      rejection_reason_out = "risk_reservation_equity_non_positive";
      return false;
     }

   double owner_token;
   if(!SM_AcquireAccountLock(owner_token, lock_timeout_ms))
     {
      rejection_reason_out = "risk_reservation_lock_timeout";
      return false;
     }
   SM_StampAccountLockHeld();

   double live_reservations = RRM_SumLiveReservationsLocked(magic);
   double projected_cash = actual_open_risk_cash + live_reservations + proposed_risk_cash;
   double projected_percent = 100.0 * projected_cash / equity;
   total_projected_percent_out = projected_percent;

   if(projected_percent > risk_cap_percent + 1e-6)
     {
      rejection_reason_out = StringFormat(
         "risk_reservation_cap_exceeded_%.4fpct_cap_%.4fpct_others_reserved_%.4f",
         projected_percent, risk_cap_percent, live_reservations);
      SM_ReleaseAccountLock(owner_token);
      return false;
     }

   string key = RRM_Key(symbol, magic);
   bool write_ok = KE_SetDoubleChecked(key, proposed_risk_cash);
   write_ok = KE_SetDoubleChecked(key + "__since", (double)TimeCurrent()) && write_ok;
   if(write_ok)
      GlobalVariablesFlush();

   SM_ReleaseAccountLock(owner_token);

   if(!write_ok)
     {
      rejection_reason_out = "risk_reservation_write_failed";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Releases this symbol+magic's own reservation once the intent it      |
//| guards has resolved (filled -- exposure is now real and counted by    |
//| ComputeOwnMagicOpenRiskCash itself -- rejected, or cancelled). Safe    |
//| to call even if no reservation is currently held (idempotent no-op). |
//| Does not require the account lock: this only clears THIS caller's     |
//| own key (identified by symbol+magic, not a shared/contended value),  |
//| so no other holder's reservation can be affected by this write.       |
//+------------------------------------------------------------------+
void RRM_ReleaseReservation(const string symbol, const long magic)
  {
   string key = RRM_Key(symbol, magic);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
   string since_key = key + "__since";
   if(GlobalVariableCheck(since_key))
      GlobalVariableDel(since_key);
  }
