//+------------------------------------------------------------------+
//| SessionManager.mqh                                                |
//| Themba Adaptive Intraday Engine — Market                          |
//|                                                                    |
//| Session-time-remaining (TASK-002_PHASE2_SPECIFICATION.md section  |
//| 1, mode-score item 4) and the daily/weekly/intraday boundary clock |
//| (section 8) — both defined against the trade SERVER'S clock only,  |
//| never an individual symbol's session calendar for the boundary     |
//| functions, per section 8's explicit "single clock" fix for mixed   |
//| metals/synthetics accounts.                                        |
//|                                                                    |
//| Deliberately stateless: this module computes "what is the current |
//| boundary" and "has a given prior boundary been crossed" as pure    |
//| functions of the server clock. It does not persist the             |
//| last-processed boundary itself — that belongs to StateManager      |
//| (TASK-003), consumed by a later RiskManager task. Keeping this      |
//| module stateless means it has no dependency on StateManager and     |
//| can be tested and reasoned about in complete isolation.             |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Start of the current server day (server-local midnight).           |
//+------------------------------------------------------------------+
datetime SN_CurrentDailyBoundary()
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| True iff the current server day's boundary is strictly after       |
//| 'last_reset_timestamp' — i.e. a new daily reset should fire. This   |
//| is the "first tick received after the boundary has passed" rule    |
//| from section 8: it does not require an exact-timestamp tick, only  |
//| that the calendar day has moved on since the last recorded reset.  |
//+------------------------------------------------------------------+
bool SN_DailyBoundaryCrossed(const datetime last_reset_timestamp)
  {
   return SN_CurrentDailyBoundary() > last_reset_timestamp;
  }

//+------------------------------------------------------------------+
//| The most recent Monday 00:05 server time at or before now, per     |
//| section 8's weekly boundary definition (the 5-minute buffer past   |
//| midnight avoids weekend-gap edge effects). MqlDateTime.day_of_week |
//| and ENUM_DAY_OF_WEEK both use 0=Sunday..6=Saturday.                 |
//+------------------------------------------------------------------+
datetime SN_CurrentWeeklyBoundary()
  {
   datetime now = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   int days_since_monday = (dt.day_of_week + 6) % 7; // Monday -> 0, Sunday -> 6
   datetime today_midnight = SN_CurrentDailyBoundary();
   datetime this_week_monday_0005 = (datetime)((long)today_midnight - (long)days_since_monday * 86400 + 5 * 60);

   if(now < this_week_monday_0005)
      return this_week_monday_0005 - 7 * 86400; // still before this week's boundary
   return this_week_monday_0005;
  }

//+------------------------------------------------------------------+
//| True iff the current weekly boundary is strictly after              |
//| 'last_reset_timestamp' — the weekly analogue of                     |
//| SN_DailyBoundaryCrossed.                                             |
//+------------------------------------------------------------------+
bool SN_WeeklyBoundaryCrossed(const datetime last_reset_timestamp)
  {
   return SN_CurrentWeeklyBoundary() > last_reset_timestamp;
  }

//+------------------------------------------------------------------+
//| True iff current server time-of-day is at or past                  |
//| boundary_hour:boundary_minute — the intraday close check, per       |
//| section 8 ("InpIntradayBoundaryServerTime, default 23:45 server     |
//| time — all of this EA's own positions ... are closed at this        |
//| time daily").                                                       |
//+------------------------------------------------------------------+
bool SN_IsPastIntradayBoundary(const int boundary_hour = 23,
                                const int boundary_minute = 45)
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   int now_minutes = dt.hour * 60 + dt.min;
   int boundary_minutes = boundary_hour * 60 + boundary_minute;
   return now_minutes >= boundary_minutes;
  }

//+------------------------------------------------------------------+
//| Section 1 item 4: fraction of today's trading session(s) remaining |
//| for 'symbol', in [0,1]. Returns false (component undefined, per     |
//| section 1's own missing-data rule — caller must exclude it, never   |
//| default it) if the symbol has no trading session today (weekend/    |
//| holiday) or its session data cannot be read.                        |
//|                                                                    |
//| Interpretation choice, stated explicitly since section 1 does not   |
//| fully pin this down for multi-session/gapped trading days: this     |
//| function measures time remaining until TODAY'S LAST session ends,   |
//| not net trading time excluding any intraday gap — a position can    |
//| still be held across a lunch-break-style gap into a later session   |
//| before the intraday close (section 8) actually forces an exit, so   |
//| "remaining" here means "time left before the trading day is fully   |
//| done", matching the mode-router's actual purpose for this input     |
//| (can a Day-trade position still be reasonably held today).          |
//+------------------------------------------------------------------+
bool SN_GetSessionMinutesRemaining(const string symbol, double &remaining_ratio)
  {
   remaining_ratio = 0.0;

   datetime now = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   datetime day_start = SN_CurrentDailyBoundary();

   long   total_seconds        = 0;
   datetime first_session_start = 0;
   datetime last_session_end    = 0;
   bool   any_session          = false;

   for(int i = 0; i < 8; i++) // generous cap on sessions per day
     {
      datetime from, to;
      if(!SymbolInfoSessionTrade(symbol, dow, i, from, to))
         break;

      // 'from'/'to' represent seconds elapsed since the start of the
      // day, not absolute dates — add them onto today's midnight.
      datetime session_start = (datetime)((long)day_start + (long)from);
      datetime session_end   = (datetime)((long)day_start + (long)to);

      total_seconds += (long)(to - from);
      if(!any_session || session_start < first_session_start)
         first_session_start = session_start;
      if(!any_session || session_end > last_session_end)
         last_session_end = session_end;
      any_session = true;
     }

   if(!any_session || total_seconds <= 0)
      return false; // no session today — undefined, caller must exclude

   double total_minutes = (double)total_seconds / 60.0;
   double remaining_minutes;

   if(now <= first_session_start)
      remaining_minutes = total_minutes;
   else if(now >= last_session_end)
      remaining_minutes = 0.0;
   else
      remaining_minutes = (double)(last_session_end - now) / 60.0;

   double ratio = remaining_minutes / total_minutes;
   if(ratio < 0.0) ratio = 0.0;
   if(ratio > 1.0) ratio = 1.0;

   remaining_ratio = ratio;
   return true;
  }
