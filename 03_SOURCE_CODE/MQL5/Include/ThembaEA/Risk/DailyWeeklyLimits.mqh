//+------------------------------------------------------------------+
//| DailyWeeklyLimits.mqh                                             |
//| Themba Adaptive Intraday Engine — Risk                             |
//|                                                                    |
//| Persisted daily/weekly equity-baseline tracking, per                |
//| TASK-002_PHASE2_SPECIFICATION.md section 8: "daily_loss_pct = 100  |
//| x (current_equity - daily_start_equity_adjusted) /                  |
//| daily_start_equity_adjusted" — i.e. actual PERIOD CHANGE, not the   |
//| absolute floating P/L defect round-3 review found. Cash-flow        |
//| (deposit/withdrawal/credit) detection uses the broker's own deal    |
//| history (DEAL_TYPE_BALANCE), the deterministic source section 8     |
//| specifies in place of the equity/balance/floating-snapshot          |
//| inference an earlier draft used.                                    |
//|                                                                    |
//| Persisted fields live in StateManager's account-wide namespace       |
//| (TASK-003), prefixed "dwl_" to avoid collision with                 |
//| EquityPeakManager's "epm_"-prefixed fields sharing the same          |
//| namespace, per section 8's account-wide key schema.                 |
//+------------------------------------------------------------------+
#property strict

#include "../Core/StateManager.mqh"
#include "../Market/SessionManager.mqh"

//+------------------------------------------------------------------+
//| Rebase the daily start-equity baseline if the daily boundary has    |
//| been crossed since the last recorded reset (first-tick-after-       |
//| boundary detection, per section 8 — no exact-timestamp tick          |
//| required). A never-initialized baseline (first run) also rebases.   |
//| Idempotent within the same day — safe to call on every tick.         |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, seventh round, P1 finding    |
//| 14):** the baseline value and its own reset timestamp are now written        |
//| under ONE lock hold (SM_SetAccountDoublesBatch) instead of two               |
//| separate SM_SetAccountDouble calls — a crash between the two previous            |
//| writes could leave a fresh equity baseline persisted WITHOUT its own                 |
//| reset timestamp advancing, so the very next tick would see                              |
//| last_reset==(the OLD timestamp) and immediately re-rebase again, silently                  |
//| discarding the intervening bar's real P/L from the loss-cap calculation.                       |
//|                                                                    |
//| **Caller contract (P1 finding 14): DWL_ApplyCashFlowAdjustments()            |
//| MUST be called BEFORE this function on every bar** (see that                    |
//| function's own header for why the ORDER matters, not just calling both              |
//| eventually) — reversed from this project's earlier call order.                          |
//+------------------------------------------------------------------+
void DWL_EnsureDailyBaseline()
  {
   datetime last_reset = (datetime)SM_GetAccountDouble("dwl_daily_reset_time", 0.0);
   if(last_reset != 0 && !SN_DailyBoundaryCrossed(last_reset))
      return; // already rebased for today — no-op

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string fields[2] = {"dwl_daily_start_equity", "dwl_daily_reset_time"};
   double values[2] = {equity, (double)SN_CurrentDailyBoundary()};
   SM_SetAccountDoublesBatch(fields, values);
  }

//+------------------------------------------------------------------+
//| Weekly analogue of DWL_EnsureDailyBaseline. Same caller-order          |
//| contract: DWL_ApplyCashFlowAdjustments() first.                          |
//+------------------------------------------------------------------+
void DWL_EnsureWeeklyBaseline()
  {
   datetime last_reset = (datetime)SM_GetAccountDouble("dwl_weekly_reset_time", 0.0);
   if(last_reset != 0 && !SN_WeeklyBoundaryCrossed(last_reset))
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string fields[2] = {"dwl_weekly_start_equity", "dwl_weekly_reset_time"};
   double values[2] = {equity, (double)SN_CurrentWeeklyBoundary()};
   SM_SetAccountDoublesBatch(fields, values);
  }

//+------------------------------------------------------------------+
//| Detects deposits/withdrawals/credits via the broker's own deal      |
//| history (DEAL_TYPE_BALANCE and DEAL_TYPE_CREDIT) since the last-     |
//| processed deal ticket, and rebases BOTH the daily and weekly         |
//| start-equity baselines by the cash-flow amount immediately — per     |
//| section 8, this prevents a cash event from distorting the loss       |
//| percentage. Scans a bounded 8-day trailing window (not full account  |
//| history) to keep the HistorySelect() call cheap on every invocation  |
//| — 8 days comfortably covers "since the last weekly reset" even       |
//| after a multi-day EA outage; see Implementation notes in             |
//| TASK-008_DAILY_WEEKLY_LIMITS.md for why a longer/unbounded window     |
//| was not used.                                                        |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, seventh round, P1 finding    |
//| 14): this MUST be called BEFORE DWL_EnsureDailyBaseline/                     |
//| DWL_EnsureWeeklyBaseline on every bar, never after** (the previous                 |
//| call order in ThembaAdaptiveIntradayEA.mq5's EvaluateAndJournal). The                   |
//| bug this closes: on a FRESH baseline capture (first-ever run, or any                       |
//| later day/week boundary rebase), the new baseline is set to CURRENT                           |
//| equity, which ALREADY reflects every historical cash flow up to that                             |
//| moment. If the cash-flow cursor (dwl_last_balance_deal_ticket) is not                               |
//| ALSO caught up to "now" at that exact same moment, the next call to THIS                               |
//| function re-applies those same already-reflected cash flows on top of                                    |
//| the fresh baseline, double-counting them (a real, since-2026-07-21                                          |
//| deposit made the daily/weekly loss percentage read as though the account                                      |
//| had lost the deposit amount a second time). Calling this function FIRST                                          |
//| means the cursor is always caught up to "now" by the time either Ensure*                                            |
//| function captures a fresh baseline from current equity immediately                                                     |
//| afterward -- that fresh baseline needs no further cash-flow adjustment                                                    |
//| because it already just happened.                                                                                            |
//|                                                                    |
//| Also fixed this round: this function's own header long claimed          |
//| "deposit/withdrawal/credit" detection, but the code only ever checked        |
//| DEAL_TYPE_BALANCE, never DEAL_TYPE_CREDIT -- a genuine credit operation          |
//| (bonus/rebate) silently did not adjust either baseline. And: a ulong            |
//| deal ticket is stored in a double (StateManager.mqh's only storage             |
//| format) -- a double can represent every integer up to 2^53 exactly, so             |
//| this is not a practical risk at today's real ticket-number scale, but a               |
//| ticket that would NOT round-trip exactly through a double is now refused                 |
//| outright (with a Print warning) rather than silently persisting a                           |
//| corrupted cursor value.                                                                         |
//+------------------------------------------------------------------+
void DWL_ApplyCashFlowAdjustments()
  {
   ulong last_ticket = (ulong)SM_GetAccountDouble("dwl_last_balance_deal_ticket", 0.0);

   datetime from = TimeTradeServer() - 8 * 86400;
   datetime to   = TimeTradeServer() + 60;
   if(!HistorySelect(from, to))
      return;

   int total = HistoryDealsTotal();
   double cash_flow_sum = 0.0;
   ulong max_ticket_seen = last_ticket;

   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0 || ticket <= last_ticket)
         continue;

      // A ticket that cannot round-trip exactly through a double must
      // never silently corrupt the persisted cursor -- refuse it and
      // leave the cursor where it was (this deal, and anything after it,
      // will be retried on the next call once/if this ever becomes a
      // real concern at this account's actual ticket scale).
      if((ulong)(double)ticket != ticket)
        {
         PrintFormat("DailyWeeklyLimits: WARNING deal ticket %I64u does not round-trip exactly "
                     "through a double -- refusing to advance the cash-flow cursor past it.",
                     ticket);
         break;
        }

      long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(deal_type == DEAL_TYPE_BALANCE || deal_type == DEAL_TYPE_CREDIT)
         cash_flow_sum += HistoryDealGetDouble(ticket, DEAL_PROFIT);

      if(ticket > max_ticket_seen)
         max_ticket_seen = ticket;
     }

   if(max_ticket_seen != last_ticket)
     {
      double daily  = SM_GetAccountDouble("dwl_daily_start_equity", 0.0) + cash_flow_sum;
      double weekly = SM_GetAccountDouble("dwl_weekly_start_equity", 0.0) + cash_flow_sum;
      string fields[3] = {"dwl_daily_start_equity", "dwl_weekly_start_equity",
                           "dwl_last_balance_deal_ticket"};
      double values[3] = {daily, weekly, (double)max_ticket_seen};
      SM_SetAccountDoublesBatch(fields, values);
     }
  }

//+------------------------------------------------------------------+
//| Signed percentage change in equity since the daily baseline —       |
//| positive for a gain, negative for a loss. Returns false (undefined) |
//| if no baseline has ever been recorded (call DWL_EnsureDailyBaseline |
//| first).                                                              |
//+------------------------------------------------------------------+
bool DWL_GetDailyChangePercent(double &change_percent)
  {
   change_percent = 0.0;
   double start = SM_GetAccountDouble("dwl_daily_start_equity", 0.0);
   if(start <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   change_percent = 100.0 * (equity - start) / start;
   return true;
  }

//+------------------------------------------------------------------+
//| Weekly analogue of DWL_GetDailyChangePercent.                        |
//+------------------------------------------------------------------+
bool DWL_GetWeeklyChangePercent(double &change_percent)
  {
   change_percent = 0.0;
   double start = SM_GetAccountDouble("dwl_weekly_start_equity", 0.0);
   if(start <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   change_percent = 100.0 * (equity - start) / start;
   return true;
  }

//+------------------------------------------------------------------+
//| True iff the daily loss cap has been breached (change_percent <=    |
//| -cap_percent). 'change_percent' is always set when a baseline        |
//| exists, so a caller can log the actual figure regardless of the      |
//| boolean outcome.                                                     |
//+------------------------------------------------------------------+
bool DWL_IsDailyLossBreached(const double cap_percent, double &change_percent)
  {
   if(!DWL_GetDailyChangePercent(change_percent))
      return false;
   return change_percent <= -cap_percent;
  }

//+------------------------------------------------------------------+
//| Weekly analogue of DWL_IsDailyLossBreached.                          |
//+------------------------------------------------------------------+
bool DWL_IsWeeklyLossBreached(const double cap_percent, double &change_percent)
  {
   if(!DWL_GetWeeklyChangePercent(change_percent))
      return false;
   return change_percent <= -cap_percent;
  }
