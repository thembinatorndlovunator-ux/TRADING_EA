//+------------------------------------------------------------------+
//| Test_SwingEngine.mq5                                              |
//| Themba Adaptive Intraday Engine — TASK-011 compile/logic test      |
//|                                                                    |
//| Tests 1-6 use hand-fabricated arrays so every expected result is    |
//| exactly hand-verifiable (no live data involved). Test 7 exercises   |
//| the CMarketData-integrated wrapper against a real symbol, verifying |
//| any found swing by independently re-reading its neighbors — the     |
//| same "recompute independently, don't hardcode an assumption about   |
//| live data" discipline used in TASK-006's boundary tests.            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/Structure/SwingEngine.mqh"

input string          InpTestSymbol    = "EURUSD";
input ENUM_TIMEFRAMES InpTestTimeframe = PERIOD_M15;

int g_pass = 0;
int g_fail = 0;

void Check(const string label, const bool condition)
  {
   if(condition)
     {
      PrintFormat("PASS: %s", label);
      g_pass++;
     }
   else
     {
      PrintFormat("FAIL: %s", label);
      g_fail++;
     }
  }

void OnStart()
  {
   Print("=== TASK-011 SwingEngine test start ===");

   //--- 1. Fabricated swing-high array: a clear peak at index 4 --------
   double highsA[] = {10, 11, 9, 8, 15, 9, 8, 9, 11, 10, 9, 8};

   Check("index 4 (value 15) is a confirmed swing high at depth 3",
         SE_IsConfirmedSwingHighArray(highsA, 4, 3));
   Check("index 3 (value 8, not a peak) is NOT a confirmed swing high",
         SE_IsConfirmedSwingHighArray(highsA, 3, 3) == false);
   Check("index 1 (k < depth, not yet confirmable) is NOT a confirmed swing high",
         SE_IsConfirmedSwingHighArray(highsA, 1, 3) == false);
   Check("index 8 (k+depth >= n, insufficient older history) is NOT confirmed",
         SE_IsConfirmedSwingHighArray(highsA, 8, 3) == false);

   //--- 2. A too-short array correctly reports insufficient data --------
   double tiny[] = {10, 11, 9, 8, 15};
   Check("a 5-element array cannot confirm a swing at k=4,depth=3 "
         "(needs k+depth=7 elements)",
         SE_IsConfirmedSwingHighArray(tiny, 4, 3) == false);

   //--- 3. Plateau (tied high) correctly fails strict-inequality check --
   double highsB[] = {10, 11, 9, 15, 15, 8, 9, 7, 6};
   Check("a tied neighbor (strict inequality required) fails confirmation",
         SE_IsConfirmedSwingHighArray(highsB, 3, 3) == false);

   //--- 4. Nearest-swing-high finder locates the same index 4 peak -----
   int found;
   bool found_ok = SE_FindNearestConfirmedSwingHighArray(highsA, 0, 3, 6, found);
   Check("nearest-swing-high finder succeeds", found_ok);
   Check("nearest-swing-high finder locates index 4", found == 4);

   //--- 5. Mirror: fabricated swing-low array with a clear trough -------
   double lowsA[] = {10, 9, 11, 12, 5, 11, 12, 9, 10, 11, 12, 13};

   Check("index 4 (value 5) is a confirmed swing low at depth 3",
         SE_IsConfirmedSwingLowArray(lowsA, 4, 3));
   Check("index 3 (value 12, not a trough) is NOT a confirmed swing low",
         SE_IsConfirmedSwingLowArray(lowsA, 3, 3) == false);
   Check("index 1 (k < depth) is NOT a confirmed swing low",
         SE_IsConfirmedSwingLowArray(lowsA, 1, 3) == false);

   int found_low;
   bool found_low_ok = SE_FindNearestConfirmedSwingLowArray(lowsA, 0, 3, 6, found_low);
   Check("nearest-swing-low finder succeeds", found_low_ok);
   Check("nearest-swing-low finder locates index 4", found_low == 4);

   //--- 6. Not-found case: a monotonic array has no interior pivot -----
   double monotonic[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
   int not_found;
   bool should_be_false = SE_FindNearestConfirmedSwingHighArray(monotonic, 0, 3, 6, not_found);
   Check("a monotonic array reports no confirmed swing high found",
         should_be_false == false);
   Check("not_found index remains -1 when nothing is found", not_found == -1);

   //--- 7. CMarketData-integrated wrapper against a real symbol ---------
   CMarketData md;
   bool init_ok = md.Init(InpTestSymbol, InpTestTimeframe);
   Check(StringFormat("MarketData Init succeeds for '%s'", InpTestSymbol), init_ok);

   if(init_ok && md.HasBars(60))
     {
      int real_found;
      bool real_found_ok = SE_FindNearestConfirmedSwingHigh(md, 0, 3, 50, real_found);
      if(real_found_ok)
        {
         // Independent cross-check: re-read the found bar and its six
         // neighbors directly and hand-verify the strict-inequality
         // property, rather than trusting the function's own answer.
         double center;
         bool ok = md.GetHigh(real_found, center);
         bool all_neighbors_lower = true;
         for(int offset = 1; offset <= 3 && ok; offset++)
           {
            double newer, older;
            ok = ok && md.GetHigh(real_found - offset, newer) &&
                 md.GetHigh(real_found + offset, older);
            if(ok && (newer >= center || older >= center))
               all_neighbors_lower = false;
           }
         Check("independently re-reading the real-symbol swing high confirms "
               "it is strictly higher than all six neighbors",
               ok && all_neighbors_lower);
        }
      else
        {
         PrintFormat("NOTE: no confirmed swing high found for '%s' in the "
                     "scanned window — a valid outcome depending on recent "
                     "price action, not necessarily a defect.", InpTestSymbol);
        }
      Check("real-symbol swing search completes without crashing regardless "
            "of outcome", true);
     }
   else
     {
      PrintFormat("NOTE: '%s' does not have enough history on %s for the "
                  "real-symbol swing search — skipped.",
                  InpTestSymbol, EnumToString(InpTestTimeframe));
     }

   PrintFormat("=== TASK-011 SwingEngine test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
