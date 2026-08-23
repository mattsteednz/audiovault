# prd-52 — Chunk N: Test Infrastructure Debt

Status: [ ] not started / [x] done
Branch: `test/infrastructure-debt`
N1–N4 can run any time; N5 MUST follow Chunk J (locks its fixes via instance
tests); N6 follows K7/K8 parser fixes.

## Tasks
- [ ] N1. REAL production migration test: replace inline onUpgrade copy in
      position_service_migration_test.dart with the shipping
      `PositionService` upgrade path — construct a v1 database using the v1
      schema exactly as git-history onCreate defined it (check `git log -p
      lib/services/position_service.dart`), open via PositionService/_onUpgrade
      chain to current version, assert: all tables/columns exist, prior rows'
      positions/status survive, bookmarks table created. Guards user data.
- [ ] N2. Shared fixtures `test/helpers/`: (a) `openTestDb()` creating an
      in-memory DB with CURRENT schema (sqflite_common_ffi) replacing the 3
      divergent schema copies across ≥8 files; (b) `registerTestLocator()`
      register/reset helper replacing duplicated boilerplate in prompt suites;
      (c) shared `stubConnectivity()` method-channel handler (2 verbatim copies
      today); (d) `testBook()` builder. Migrate files incrementally; suite must
      stay green per commit.
- [ ] N3. kiri_check tautologies (library_helpers_test.dart): delete Property 6
      (:502-522 same-expression equality) and Property 7 (:525-547 self-built
      comparison); rewrite Property 5 (:446-499) to use non-trivially populated
      statuses map so it can fail.
- [ ] N4. position_persister_test timing test (:198-204 real 70ms sleeps) →
      fake_async (dep already present; see drive_removal_scheduler_test as
      template).
- [ ] N5. KowhaiHandler instance tests (HIGH IMPACT — after J): extract minimal
      seams (@visibleForTesting ctor params or factory hooks: AudioPlayer,
      CastController, Persister collaborators already closure-injected — audit).
      Cover: loadBook resume-from-DB; loadBook failure resets state+rethrows;
      play smart-rewind boundaries; pause persists (incl. unawaited-cast branch
      now awaited per J); skipToNext/Previous chapter edges; completion →
      finished + removal scheduled; stop single-save + cast teardown (J4);
      casting loadBook handoff keeps new book's saved position (J2/J3).
      Target: the six bug classes in prd-48 each have a red/green regression
      test.
- [ ] N6. Parser edge tests: m4b QuickTime track happy path + UTF-16BE titles +
      64-bit box sizes (currently 0% coverage); opf default-namespace fixture
      (pairs with K8).
- [ ] N7. Gate green; commits grouped: `test(db): exercise production
      migrations`, `chore(test): shared fixtures`, `test(handler): playback
      lifecycle coverage`.
