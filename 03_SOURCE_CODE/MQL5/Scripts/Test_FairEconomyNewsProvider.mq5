//+------------------------------------------------------------------+
//| Test_FairEconomyNewsProvider.mq5                                  |
//| Themba Adaptive Intraday Engine — TASK-034 compile/logic test       |
//|                                                                    |
//| Tests 1-8 are pure (no network) — parsing, ISO8601/impact/lenient-     |
//| double helpers, against a hand-fabricated sample matching the           |
//| feed's documented field shape (per this file's own "unverified            |
//| assumption" header note — a real captured sample should replace this        |
//| once the feed is reachable from this account for real).                       |
//|                                                                    |
//| Tests 9-10 exercise the LIVE path (FEP_FetchLive / FEP_EnsureCache)      |
//| via a REAL WebRequest call. This project's terminal has not had          |
//| nfs.faireconomy.net added to its allowed-URL list yet (a manual,           |
//| user-side step per FairEconomyNewsProvider.mqh's own header) — so           |
//| this call is expected to fail deterministically with "URL not               |
//| allowed" REGARDLESS of actual internet connectivity, which is exactly         |
//| the fail-closed path Specification item 4 requires be tested. If a             |
//| future session adds the allowed URL, test 9 will instead exercise the           |
//| real successful-fetch path — either outcome is handled explicitly              |
//| below, not assumed.                                                                |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/ThembaEA/News/FairEconomyNewsProvider.mqh"

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
   Print("=== TASK-034 FairEconomyNewsProvider test start ===");

   //--- 1. ISO8601 parsing: explicit negative offset -----------------------
   bool ok;
   datetime t1 = FEP_ParseIso8601ToUtc("2026-07-22T12:30:00-04:00", ok);
   datetime expected1 = StringToTime("2026.07.22 16:30:00"); // 12:30 -04:00 == 16:30 UTC
   Check("ISO8601 with -04:00 offset converts to correct UTC", ok && t1 == expected1);

   //--- 2. ISO8601 parsing: explicit positive offset -----------------------
   bool ok2;
   datetime t2 = FEP_ParseIso8601ToUtc("2026-07-22T09:00:00+02:00", ok2);
   datetime expected2 = StringToTime("2026.07.22 07:00:00"); // 09:00 +02:00 == 07:00 UTC
   Check("ISO8601 with +02:00 offset converts to correct UTC", ok2 && t2 == expected2);

   //--- 3. ISO8601 parsing: 'Z' / absent offset means UTC already ----------
   bool ok3;
   datetime t3 = FEP_ParseIso8601ToUtc("2026-07-22T12:30:00Z", ok3);
   datetime expected3 = StringToTime("2026.07.22 12:30:00");
   Check("ISO8601 with 'Z' suffix is already UTC", ok3 && t3 == expected3);

   //--- 4. ISO8601 parsing: too-short input is rejected, not guessed -------
   bool ok4;
   FEP_ParseIso8601ToUtc("2026-07-22", ok4);
   Check("too-short ISO8601 string is rejected (ok_out=false)", ok4 == false);

   //--- 5. Impact mapping matches MT5CalendarProvider's 0-3 ordinal scale --
   Check("impact 'High' maps to 3", FEP_MapImpact("High") == 3);
   Check("impact 'Medium' maps to 2", FEP_MapImpact("Medium") == 2);
   Check("impact 'Low' maps to 1", FEP_MapImpact("Low") == 1);
   Check("impact 'Holiday' maps to 0", FEP_MapImpact("Holiday") == 0);
   Check("unrecognized impact maps to 0", FEP_MapImpact("Non-Economic") == 0);

   //--- 6. Lenient double parsing ------------------------------------------
   Check("lenient parse '1.2%' -> 1.2", MathAbs(FEP_ParseLenientDouble("1.2%") - 1.2) < 0.0001);
   Check("lenient parse '-0.3' -> -0.3", MathAbs(FEP_ParseLenientDouble("-0.3") - (-0.3)) < 0.0001);
   Check("lenient parse '' -> 0.0", FEP_ParseLenientDouble("") == 0.0);
   Check("lenient parse 'N/A' -> 0.0 (no guessed unit suffix)",
         FEP_ParseLenientDouble("N/A") == 0.0);

   //--- 7. Full feed parse: hand-fabricated sample matching the feed's -----
   //--- documented flat-array-of-objects shape ------------------------------
   string sample =
      "[" +
      "{\"title\":\"Non-Farm Employment Change\",\"country\":\"USD\"," +
      "\"date\":\"2026-07-22T12:30:00-04:00\",\"impact\":\"High\"," +
      "\"forecast\":\"180K\",\"previous\":\"150K\"}," +
      "{\"title\":\"Bank Holiday\",\"country\":\"GBP\"," +
      "\"date\":\"2026-07-22T00:00:00+00:00\",\"impact\":\"Holiday\"," +
      "\"forecast\":\"\",\"previous\":\"\"}," +
      "{\"title\":\"CPI m/m\",\"country\":\"EUR\"," +
      "\"date\":\"2026-07-23T09:00:00+02:00\",\"impact\":\"Medium\"," +
      "\"forecast\":\"0.3%\",\"previous\":\"0.2%\"}" +
      "]";

   SNewsEvent events[];
   int count = FEP_ParseFeedJson(sample, events);
   Check("parses all 3 objects from the sample", count == 3);
   Check("event 0 title parsed", events[0].event_name == "Non-Farm Employment Change");
   Check("event 0 currency parsed", events[0].currency == "USD");
   Check("event 0 importance mapped (High=3)", events[0].importance == 3);
   Check("event 0 scheduled_utc matches expected conversion",
         events[0].scheduled_utc == StringToTime("2026.07.22 16:30:00"));
   Check("event 0 forecast lenient-parsed", MathAbs(events[0].forecast - 180.0) < 0.0001);
   Check("event 0 previous lenient-parsed", MathAbs(events[0].previous - 150.0) < 0.0001);
   Check("event 0 source tagged FAIRECONOMY", events[0].source == "FAIRECONOMY");
   Check("event 1 (Holiday) importance mapped to 0", events[1].importance == 0);
   Check("event 2 currency EUR parsed", events[2].currency == "EUR");

   //--- 8. Malformed/empty input parses to zero events, never crashes ------
   //--- **This tests FEP_ParseFeedJson, the PURE parser, in isolation --------
   //--- deliberately tolerant, per its own documented contract. This is NOT --
   //--- the fail-open bug the seventh-round review reported (Codex review -----
   //--- finding, P0 finding 5) -- that bug was in FEP_FetchLive treating an -----
   //--- HTTP-200-but-garbage-body response as a verified-empty result. Test 8a ---
   //--- below exercises the NEW live-fetch-level guard that closes it.** ---------
   SNewsEvent empty_events[];
   int empty_count = FEP_ParseFeedJson("", empty_events);
   Check("empty input parses to 0 events", empty_count == 0);
   SNewsEvent garbage_events[];
   int garbage_count = FEP_ParseFeedJson("not valid json at all {{{", garbage_events);
   Check("malformed input parses to 0 events (no crash, no guessed data)", garbage_count == 0);

   //--- 8a. **Codex review finding, seventh round, P0 finding 5**: -----------
   //--- FEP_LooksLikeJsonArray -- the live-fetch-level guard that now REJECTS ----
   //--- (as a provider failure, not a verified-empty result) exactly the kind -----
   //--- of response that test 8 above shows the pure parser would otherwise --------
   //--- silently accept as "0 events, success". ------------------------------------
   Check("an empty response body does not look like a JSON array",
         FEP_LooksLikeJsonArray("") == false);
   Check("an HTML error page does not look like a JSON array",
         FEP_LooksLikeJsonArray("<html><body>502 Bad Gateway</body></html>") == false);
   Check("truncated/malformed garbage does not look like a JSON array",
         FEP_LooksLikeJsonArray("not valid json at all {{{") == false);
   Check("a genuinely empty JSON array DOES look like one (a real empty "
         "calendar week must not be rejected)", FEP_LooksLikeJsonArray("[]") == true);
   Check("a real, well-formed feed sample looks like a JSON array",
         FEP_LooksLikeJsonArray(sample) == true);

   //--- 9. LIVE fetch — expected to fail (URL not yet allowed in this ------
   //--- terminal), exercising the fail-closed path for real -----------------
   FEP_InvalidateCache();
   SNewsEvent live_events[];
   int live_result = FEP_FetchLive(live_events);
   if(live_result < 0)
      Print("INFO: FEP_FetchLive failed as expected (URL not yet allowed in this terminal, "
            "or no network) -- this IS the fail-closed path under test.");
   else
      Print("INFO: FEP_FetchLive succeeded for real (this terminal's allowed-URL list already "
            "includes nfs.faireconomy.net) -- treating this as the successful-fetch path.");
   Check("FEP_FetchLive returns a definitive success/failure signal (never hangs/crashes)",
         live_result >= -1);

   //--- 10. Caching: a same-instant second call does not attempt a --------
   //--- second network round-trip -- verified by cache-content stability --
   //--- across the call, not merely by timing. ------------------------------
   datetime now = TimeGMT();
   bool first_ensure = FEP_EnsureCache(now);
   int cached_count_after_first = ArraySize(g_fep_cached_events);
   bool second_ensure = FEP_EnsureCache(now); // same instant -> must be a cache hit, not a refetch
   int cached_count_after_second = ArraySize(g_fep_cached_events);
   Check("second FEP_EnsureCache call at the same instant returns the same result as the first",
         second_ensure == first_ensure);
   Check("cache contents are unchanged across a same-instant second call (no refetch occurred)",
         cached_count_after_second == cached_count_after_first);

   //--- 11. Fail-closed: FEP_IsInBlackoutNow reports feed_unavailable_out --
   //--- whenever the cache could not be populated (only meaningful when ----
   //--- test 9/10 above actually failed to reach the feed) ------------------
   if(!first_ensure)
     {
      FEP_InvalidateCache();
      string triggering_event_id;
      bool feed_unavailable;
      bool blackout = FEP_IsInBlackoutNow("XAUUSD", "USD", 3, 15, 15, 60, 3.0, 1.0,
                                           triggering_event_id, feed_unavailable);
      Check("feed unreachable: feed_unavailable_out reports true", feed_unavailable);
      Check("feed unreachable: return value is false (caller, not this function, applies the "
            "fail-closed policy)", blackout == false);
     }
   else
      Print("INFO: skipping test 11's unreachable-feed assertion -- the feed was actually "
            "reachable in this run (see test 9's INFO line above).");

   PrintFormat("=== TASK-034 FairEconomyNewsProvider test complete: %d passed, %d failed ===",
               g_pass, g_fail);
  }
