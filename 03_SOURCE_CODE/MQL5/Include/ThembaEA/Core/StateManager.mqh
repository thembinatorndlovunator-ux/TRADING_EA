//+------------------------------------------------------------------+
//| StateManager.mqh                                                 |
//| Themba Adaptive Intraday Engine — Core                           |
//|                                                                    |
//| Account-wide scalar persistence, per TASK-002_PHASE2_             |
//| SPECIFICATION.md section 8 ("Persistence and restart") and        |
//| section 11 (StateManager test boundary).                          |
//|                                                                    |
//| Scope of this module (TASK-003): the ACCOUNT-WIDE namespace only  |
//| (account_login + trade_server, deliberately unpartitioned by      |
//| magic/symbol, per section 8's two-namespace schema). Per-instance |
//| (symbol+magic+account+server) structured/file-based storage is    |
//| out of scope here and is a separate, later task — this keeps this |
//| task bounded, per CLAUDE.md's "implement one bounded task" rule.  |
//|                                                                    |
//| Storage mechanism: native MQL5 global variables                   |
//| (GlobalVariableSet/Get), which are double-only and persist across |
//| terminal restarts — exactly the "small scalar" storage the        |
//| specification calls for (daily/weekly equity baselines, peak      |
//| equity, reset timestamps, schema version).                        |
//|                                                                    |
//| Concurrency: a compare-and-set lock built on                      |
//| GlobalVariableSetOnCondition, per section 8's "single-writer"      |
//| requirement, with stale-lock breaking so a crashed instance can    |
//| never permanently wedge the lock.                                 |
//|                                                                    |
//| Schema: every account-wide record set is versioned. A version      |
//| mismatch triggers SM_EnsureAccountSchema()'s targeted migration —  |
//| per section 8, a mismatch must never blanket-reset a still-valid   |
//| period-loss baseline; this module's migration hook is additive     |
//| only (it may add new fields with defaults) and never deletes an   |
//| existing field.                                                   |
//+------------------------------------------------------------------+
#property strict

// Current schema version implemented by this build of StateManager.
// Bump this, and extend SM_EnsureAccountSchema()'s migration branch,
// whenever a new account-wide field is introduced by a later task.
#define SM_SCHEMA_VERSION 1.0

// Lock is considered abandoned (crashed holder) after this many seconds
// and force-broken by the next caller — prevents a permanent wedge.
#define SM_LOCK_STALE_SECONDS 30

//+------------------------------------------------------------------+
//| Namespace: account_login + trade_server, per section 8.           |
//| Deliberately excludes symbol/magic — this is the account-wide     |
//| namespace, shared by every instance of this EA on this account.   |
//+------------------------------------------------------------------+
string SM_AccountNamespace()
  {
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   return "ThembaEA_AW_" + IntegerToString(login) + "_" + server;
  }

//+------------------------------------------------------------------+
//| Fully-qualified global-variable name for one account-wide field.  |
//+------------------------------------------------------------------+
string SM_AccountKey(const string field)
  {
   return SM_AccountNamespace() + "__" + field;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** creates the lock variable exactly once, meant to be called          |
//| ONLY from OnInit -- never from SM_AcquireAccountLock's own hot path            |
//| (see that function's own fix comment for why). MQL5 native global               |
//| variables have no atomic create-if-absent primitive                                |
//| (GlobalVariableSetOnCondition fails outright against a variable that                  |
//| does not exist yet), so this bootstrap-once-at-OnInit is the SAME                        |
//| practical mitigation already established and accepted for                                    |
//| IntentManager.mqh's own identical create-if-absent race (round 7, P0                            |
//| finding 1) -- it narrows the race window from "every single lock                                    |
//| acquisition attempt, forever" to "once, at EA startup," not a fully                                     |
//| airtight fix.                                                                                             |
//+------------------------------------------------------------------+
void SM_EnsureAccountLockInitialized()
  {
   string lock_key = SM_AccountKey("lock");
   if(!GlobalVariableCheck(lock_key))
      GlobalVariableSet(lock_key, 0.0); // unlocked sentinel
   if(!GlobalVariableCheck(lock_key + "__since"))
      GlobalVariableSet(lock_key + "__since", 0.0);
  }

//+------------------------------------------------------------------+
//| Acquire the account-wide write lock (compare-and-set).             |
//| Returns true once acquired, false on timeout.                      |
//| A lock held longer than SM_LOCK_STALE_SECONDS is treated as        |
//| abandoned (its holder crashed without releasing it) and broken.    |
//|                                                                    |
//| **Fixed, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** this previously did its own "if(!GlobalVariableCheck) ... Set"      |
//| bootstrap on EVERY call -- a check-then-unconditional-set that is NOT        |
//| atomic as a unit. Two instances racing the very first ever call on this        |
//| account+server could interleave so instance A's late, unconditional               |
//| GlobalVariableSet(lock_key, 0.0) OVERWRITES instance B's own already-                 |
//| legitimately-acquired lock (set to 1.0) back to "unlocked", letting a                    |
//| THIRD instance also acquire it concurrently -- precisely the same class                     |
//| of bug the intent-manager race fix (round 7, P0 finding 1) already closed                       |
//| for a different lock. The bootstrap now runs exactly once, from OnInit                              |
//| (SM_EnsureAccountLockInitialized), never from this hot path.**                                          |
//+------------------------------------------------------------------+
bool SM_AcquireAccountLock(const int timeout_ms = 500)
  {
   string lock_key = SM_AccountKey("lock");

   ulong start_tick = GetTickCount64();
   while(true)
     {
      // Atomic: set to 1.0 only if currently 0.0 (unlocked).
      if(GlobalVariableSetOnCondition(lock_key, 1.0, 0.0))
         return true;

      // Someone else holds it — check for staleness.
      datetime held_since = (datetime)GlobalVariableGet(lock_key + "__since");
      if(held_since > 0 && (TimeCurrent() - held_since) > SM_LOCK_STALE_SECONDS)
        {
         // Force-break an abandoned lock, then retry immediately.
         GlobalVariableSet(lock_key, 0.0);
         continue;
        }

      if((GetTickCount64() - start_tick) >= (ulong)timeout_ms)
         return false;

      Sleep(10);
     }
   return false; // unreachable — satisfies MQL5's control-path analysis
  }

//+------------------------------------------------------------------+
//| Release the account-wide write lock.                               |
//+------------------------------------------------------------------+
void SM_ReleaseAccountLock()
  {
   string lock_key = SM_AccountKey("lock");
   GlobalVariableSet(lock_key, 0.0);
   GlobalVariableSet(lock_key + "__since", 0.0);
  }

//+------------------------------------------------------------------+
//| Internal: stamp the lock's acquisition time. Call immediately     |
//| after a successful SM_AcquireAccountLock() when the caller intends |
//| to hold it for more than a trivial instant (enables staleness      |
//| detection for other callers).                                      |
//+------------------------------------------------------------------+
void SM_StampAccountLockHeld()
  {
   GlobalVariableSet(SM_AccountKey("lock") + "__since", (double)TimeCurrent());
  }

//+------------------------------------------------------------------+
//| Set one account-wide double field. Lock-guarded (single-writer).   |
//| Returns false if the lock could not be acquired within timeout.    |
//+------------------------------------------------------------------+
bool SM_SetAccountDouble(const string field, const double value,
                          const int lock_timeout_ms = 500)
  {
   if(!SM_AcquireAccountLock(lock_timeout_ms))
      return false;
   SM_StampAccountLockHeld();

   GlobalVariableSet(SM_AccountKey(field), value);

   SM_ReleaseAccountLock();
   return true;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, seventh round, P1 finding  |
//| 14):** sets MULTIPLE account-wide double fields under ONE lock            |
//| acquisition — the single-field SM_SetAccountDouble above acquires and       |
//| releases the lock PER CALL, so a caller updating several logically-           |
//| related fields (e.g. a baseline value alongside its own reset                    |
//| timestamp, or a cash-flow-adjusted baseline alongside the cursor that                |
//| tracks which deals have already been applied) leaves a real crash-window                |
//| between those separate writes.                                                                   |
//|                                                                    |
//| **Corrected, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** the claim this previously made here -- "a crash either sees none of       |
//| them applied or all of them" -- is FALSE and has been removed. MQL5 native           |
//| global variables have no multi-field transactional commit primitive: this               |
//| lock only serializes against OTHER CONCURRENT WRITERS (no interleaving              |
//| between two callers' field writes), it does NOT make the writes atomic                   |
//| against THIS PROCESS crashing partway through the loop below -- a crash                     |
//| after field 0 but before field 1 leaves field 0 updated and field 1 stale.                      |
//| The real, honest guarantee callers get is weaker: EVERY CALLER OF THIS                            |
//| FUNCTION MUST ORDER ITS OWN fields[]/values[] SO THE LAST ELEMENT IS THE                              |
//| ONE A READER TREATS AS THE "IS THIS FRESH?" SIGNAL (e.g. a reset                                        |
//| timestamp, or a cursor) -- a crash before that final write leaves the                                       |
//| signal stale, so the next read naturally re-triggers an idempotent retry                                        |
//| of the whole batch rather than silently trusting a half-applied one. Both                                           |
//| existing callers (DailyWeeklyLimits.mqh's DWL_EnsureDailyBaseline/                                                     |
//| DWL_EnsureWeeklyBaseline/DWL_ApplyCashFlowAdjustments) already follow this                                                 |
//| convention. This is self-healing for THIS project's specific idempotent-                                                      |
//| retry-driven callers, not general transactional atomicity -- a future                                                             |
//| caller that is NOT idempotent-retry-safe must not assume this function                                                                |
//| gives it a real all-or-nothing guarantee.                                                                                                |
//+------------------------------------------------------------------+
bool SM_SetAccountDoublesBatch(const string &fields[], const double &values[],
                                 const int lock_timeout_ms = 500)
  {
   int n = ArraySize(fields);
   if(n != ArraySize(values) || n == 0)
      return false;

   if(!SM_AcquireAccountLock(lock_timeout_ms))
      return false;
   SM_StampAccountLockHeld();

   for(int i = 0; i < n; i++)
      GlobalVariableSet(SM_AccountKey(fields[i]), values[i]);

   SM_ReleaseAccountLock();
   return true;
  }

//+------------------------------------------------------------------+
//| **Added, 2026-07-22 (Codex review finding, eighth round, P0 finding    |
//| 4):** atomically raises one account-wide double field to 'candidate' ONLY     |
//| if it exceeds the field's current stored value (or the field has never          |
//| been set) -- holds the account lock across the READ, COMPARE, and WRITE            |
//| as one critical section. EquityPeakManager.mqh's peak-tracking functions               |
//| previously did their own separate SM_GetAccountDouble() read followed by                   |
//| a conditional SM_SetAccountDouble() call -- each individually lock-guarded,                    |
//| but the read and the write were NOT under the same lock hold, so two                              |
//| concurrent instances could interleave: both read the same (lower) current                            |
//| peak, both compute "my equity is higher, write it", and whichever write                                  |
//| lands SECOND wins even if its own equity reading was the LOWER of the two --                                 |
//| silently losing a genuine peak update. Returns false only if the lock                                            |
//| could not be acquired within timeout (fail-closed for the caller to treat                                            |
//| as "peak state unknown this tick", never "no update needed").                                                        |
//+------------------------------------------------------------------+
bool SM_SetAccountDoubleIfGreater(const string field, const double candidate,
                                   const int lock_timeout_ms = 500)
  {
   if(!SM_AcquireAccountLock(lock_timeout_ms))
      return false;
   SM_StampAccountLockHeld();

   string key    = SM_AccountKey(field);
   bool   exists = GlobalVariableCheck(key);
   double current = exists ? GlobalVariableGet(key) : 0.0;
   if(!exists || candidate > current)
      GlobalVariableSet(key, candidate);

   SM_ReleaseAccountLock();
   return true;
  }

//+------------------------------------------------------------------+
//| Read one account-wide double field. Returns default_value if the   |
//| field has never been set. Reads are not lock-guarded (a torn read  |
//| is impossible — GlobalVariableGet returns one already-committed    |
//| double atomically at the platform level).                          |
//+------------------------------------------------------------------+
double SM_GetAccountDouble(const string field, const double default_value)
  {
   string key = SM_AccountKey(field);
   if(!GlobalVariableCheck(key))
      return default_value;
   return GlobalVariableGet(key);
  }

//+------------------------------------------------------------------+
//| True if an account-wide field has ever been set.                   |
//+------------------------------------------------------------------+
bool SM_AccountFieldExists(const string field)
  {
   return GlobalVariableCheck(SM_AccountKey(field));
  }

//+------------------------------------------------------------------+
//| Delete one account-wide field (used only by tests / explicit       |
//| operator reset actions — never called by normal risk logic).       |
//+------------------------------------------------------------------+
void SM_DeleteAccountField(const string field)
  {
   string key = SM_AccountKey(field);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
  }

//+------------------------------------------------------------------+
//| Current stored schema version (0.0 if never initialized).          |
//+------------------------------------------------------------------+
double SM_GetAccountSchemaVersion()
  {
   return SM_GetAccountDouble("schema_version", 0.0);
  }

//+------------------------------------------------------------------+
//| Ensure the account-wide record set matches SM_SCHEMA_VERSION.      |
//|                                                                    |
//| Per section 8: a version mismatch performs a TARGETED migration —  |
//| it may only add fields that did not exist under the old version,   |
//| defaulted to a neutral value; it must never reset or delete a      |
//| still-valid field (in particular, never the daily/weekly equity    |
//| baselines once those fields exist, from a later task onward).      |
//|                                                                    |
//| At schema 1.0 there is nothing to migrate from (this is the first  |
//| version) — calling this simply stamps the version on first use.    |
//| Future schema bumps extend the if-chain below additively; they     |
//| must not remove an existing branch or add a blanket reset.         |
//+------------------------------------------------------------------+
void SM_EnsureAccountSchema(const int lock_timeout_ms = 500)
  {
   double stored = SM_GetAccountSchemaVersion();
   if(stored == SM_SCHEMA_VERSION)
      return; // already current — no-op, nothing touched.

   if(!SM_AcquireAccountLock(lock_timeout_ms))
      return; // caller may retry on a later tick; never blocks trading.
   SM_StampAccountLockHeld();

   // stored == 0.0 means "never initialized" — first run on this
   // account+server. Every future migration branch below must be
   // additive only (see header comment).
   if(stored == 0.0)
     {
      // No pre-existing fields to preserve; just stamp the version.
      GlobalVariableSet(SM_AccountKey("schema_version"), SM_SCHEMA_VERSION);
     }
   // else if(stored == 1.0 && SM_SCHEMA_VERSION == 2.0) { ... additive
   //    migration for a future schema bump goes here ... }

   SM_ReleaseAccountLock();
  }
