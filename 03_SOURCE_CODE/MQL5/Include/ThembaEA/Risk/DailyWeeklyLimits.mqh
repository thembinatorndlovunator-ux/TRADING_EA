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
//+------------------------------------------------------------------+
void DWL_EnsureDailyBaseline()
  {
   datetime last_reset = (datetime)SM_GetAccountDouble("dwl_daily_reset_time", 0.0);
   if(last_reset != 0 && !SN_DailyBoundaryCrossed(last_reset))
      return; // already rebased for today — no-op

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   SM_SetAccountDouble("dwl_daily_start_equity", equity);
   SM_SetAccountDouble("dwl_daily_reset_time", (double)SN_CurrentDailyBoundary());
  }

//+------------------------------------------------------------------+
//| Weekly analogue of DWL_EnsureDailyBaseline.                          |
//+------------------------------------------------------------------+
void DWL_EnsureWeeklyBaseline()
  {
   datetime last_reset = (datetime)SM_GetAccountDouble("dwl_weekly_reset_time", 0.0);
   if(last_reset != 0 && !SN_WeeklyBoundaryCrossed(last_reset))
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   SM_SetAccountDouble("dwl_weekly_start_equity", equity);
   SM_SetAccountDouble("dwl_weekly_reset_time", (double)SN_CurrentWeeklyBoundary());
  }

//+------------------------------------------------------------------+
//| Detects deposits/withdrawals/credits via the broker's own deal      |
//| history (DEAL_TYPE_BALANCE) since the last-processed deal ticket,   |
//| and rebases BOTH the daily and weekly start-equity baselines by      |
//| the cash-flow amount immediately — per section 8, this prevents a   |
//| cash event from distorting the loss percentage. Scans a bounded      |
//| 8-day trailing window (not full account history) to keep the        |
//| HistorySelect() call cheap on every invocation — 8 days comfortably  |
//| covers "since the last weekly reset" even after a multi-day EA       |
//| outage; see Implementation notes in TASK-008_DAILY_WEEKLY_LIMITS.md  |
//| for why a longer/unbounded window was not used.                      |
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

      long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(deal_type == DEAL_TYPE_BALANCE)
         cash_flow_sum += HistoryDealGetDouble(ticket, DEAL_PROFIT);

      if(ticket > max_ticket_seen)
         max_ticket_seen = ticket;
     }

   if(cash_flow_sum != 0.0)
     {
      double daily  = SM_GetAccountDouble("dwl_daily_start_equity", 0.0);
      double weekly = SM_GetAccountDouble("dwl_weekly_start_equity", 0.0);
      SM_SetAccountDouble("dwl_daily_start_equity", daily + cash_flow_sum);
      SM_SetAccountDouble("dwl_weekly_start_equity", weekly + cash_flow_sum);
     }

   if(max_ticket_seen != last_ticket)
      SM_SetAccountDouble("dwl_last_balance_deal_ticket", (double)max_ticket_seen);
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
