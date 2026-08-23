/// Preservation property tests for book-download-prompt-fixes.
///
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**
///
/// These tests encode the EXISTING (baseline) behavior that must be preserved
/// after the fix is applied. They are written to PASS on unfixed code and
/// must continue to pass after the fix.
///
/// Property 2: Preservation — Mobile Data Path and Direct Navigation Unchanged
///
/// Preservation cases tested:
///   3.1 / 3.2 — Mobile-data path: `_showDriveDownloadSheet` shows the
///     mobile-data warning message with formatted size and annotates the
///     Download button label with the size.
///   3.3 — Fully downloaded Drive book: "Start listening" navigates directly
///     to PlayerScreen without showing the download sheet.
///   3.4 — Local book: "Start listening" navigates directly to PlayerScreen
///     without showing the download sheet.
///   3.5 — "Download to device" OutlinedButton: tapping it calls
///     `DriveLibraryService.startDownload` and does NOT show a bottom sheet.
///   3.6 — Library screen card tap for undownloaded Drive book: shows the
///     download prompt (existing `_openPlayer` path is unchanged).
///
/// IMPORTANT: This file does NOT import `lib/utils/drive_download_sheet.dart`
/// because that file does not exist on unfixed code. The mobile-data path is
/// tested through the LibraryScreen widget (tapping an undownloaded Drive book
/// card while on mobile data), which calls the private `_showDriveDownloadSheet`
/// method internally.
///
/// EXPECTED OUTCOME: All tests PASS on unfixed code (confirms baseline behavior).
/// EXPECTED OUTCOME: All tests continue to PASS after the fix is implemented.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import 'package:kowhai/locator.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/models/availability_filter_state.dart';
import 'package:kowhai/screens/book_details_screen.dart';
import 'package:kowhai/screens/library_screen.dart';
import 'package:kowhai/screens/player_screen.dart';
import 'package:kowhai/services/drive_book_repository.dart';
import 'package:kowhai/services/drive_download_manager.dart';
import 'package:kowhai/services/drive_library_service.dart';
import 'package:kowhai/services/drive_service.dart';
import 'package:kowhai/services/enrichment_service.dart';
import 'package:kowhai/services/position_service.dart';
import 'package:kowhai/services/preferences_service.dart';
import 'package:kowhai/services/scanner_service.dart';
import 'package:kowhai/services/sleep_timer_controller.dart';
import 'package:kowhai/services/audio_handler.dart';
import 'package:kowhai/widgets/audio_handler_scope.dart';

import 'book_download_prompt_preservation_test.mocks.dart';

// ---------------------------------------------------------------------------
// Minimal fake KowhaiHandler for tests
// ---------------------------------------------------------------------------

/// A minimal fake [KowhaiHandler] that provides the streams and state
/// needed by [AudioHandlerScope]-dependent widgets without requiring a real
/// audio player or service locator setup.
class _FakeAudioHandler extends KowhaiHandler {
  final _playbackStateSubject =
      BehaviorSubject<PlaybackState>.seeded(PlaybackState());

  @override
  BehaviorSubject<PlaybackState> get playbackState => _playbackStateSubject;

  @override
  Audiobook? get currentBook => null;
}

// ---------------------------------------------------------------------------
// Mock generation
// ---------------------------------------------------------------------------

@GenerateMocks([
  DriveLibraryService,
  DriveBookRepository,
  DriveDownloadManager,
  EnrichmentService,
  PositionService,
  PreferencesService,
  ScannerService,
  SleepTimerController,
])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Shared test fixtures ──────────────────────────────────────────────────

  /// An undownloaded Drive book: source=drive, audioFiles empty, 3 files in Drive.
  /// totalSizeBytes for folderId 'folder-123' is stubbed to 257,363,968 bytes
  /// ≈ 245.3 MB.
  const undownloadedDriveBook = Audiobook(
    title: 'Test Drive Book',
    path: '/drive/test-drive-book',
    audioFiles: [],
    source: AudiobookSource.drive,
    driveMetadata: DriveBookMeta(
      folderId: 'folder-123',
      folderName: 'Test Drive Book',
      isShared: false,
      totalFileCount: 3,
    ),
  );

  /// A fully downloaded Drive book: audioFiles.length (3) >= totalFileCount (3).
  const fullyDownloadedDriveBook = Audiobook(
    title: 'Downloaded Drive Book',
    path: '/drive/downloaded-drive-book',
    audioFiles: [
      '/local/file1.mp3',
      '/local/file2.mp3',
      '/local/file3.mp3',
    ],
    source: AudiobookSource.drive,
    driveMetadata: DriveBookMeta(
      folderId: 'folder-456',
      folderName: 'Downloaded Drive Book',
      isShared: false,
      totalFileCount: 3,
    ),
  );

  /// A local book: source=local, audioFiles non-empty.
  const localBook = Audiobook(
    title: 'Local Book',
    path: '/local/local-book',
    audioFiles: ['/local/local-book/chapter1.mp3'],
    source: AudiobookSource.local,
  );

  // ── Service mocks ─────────────────────────────────────────────────────────

  late MockDriveLibraryService mockDriveLibraryService;
  late MockDriveBookRepository mockDriveBookRepository;
  late MockDriveDownloadManager mockDriveDownloadManager;
  late MockEnrichmentService mockEnrichmentService;
  late MockPositionService mockPositionService;
  late MockPreferencesService mockPreferencesService;
  late MockScannerService mockScannerService;
  late MockSleepTimerController mockSleepTimerController;
  late _FakeAudioHandler fakeAudioHandler;

  setUp(() {
    mockDriveLibraryService = MockDriveLibraryService();
    mockDriveBookRepository = MockDriveBookRepository();
    mockDriveDownloadManager = MockDriveDownloadManager();
    mockEnrichmentService = MockEnrichmentService();
    mockPositionService = MockPositionService();
    mockPreferencesService = MockPreferencesService();
    mockScannerService = MockScannerService();
    mockSleepTimerController = MockSleepTimerController();

    // ── Register mocks in the service locator FIRST ───────────────────────
    // KowhaiHandler constructor calls locator<PositionService>() and
    // locator<PreferencesService>(), so these must be registered before
    // creating _FakeAudioHandler.
    locator.allowReassignment = true;
    locator.registerLazySingleton<DriveLibraryService>(
        () => mockDriveLibraryService);
    locator.registerLazySingleton<DriveBookRepository>(
        () => mockDriveBookRepository);
    locator.registerLazySingleton<DriveDownloadManager>(
        () => mockDriveDownloadManager);
    locator.registerLazySingleton<EnrichmentService>(
        () => mockEnrichmentService);
    locator.registerLazySingleton<PositionService>(
        () => mockPositionService);
    locator.registerLazySingleton<PreferencesService>(
        () => mockPreferencesService);
    locator.registerLazySingleton<ScannerService>(
        () => mockScannerService);
    locator.registerLazySingleton<SleepTimerController>(
        () => mockSleepTimerController);
    // DriveService: register a real instance so currentAccount == null
    // (Drive not connected), which causes _initLibrary to reset the
    // availability filter to `all` — the correct state for these tests.
    locator.registerLazySingleton<DriveService>(() => DriveService());

    // ── DriveDownloadManager ──────────────────────────────────────────────
    when(mockDriveDownloadManager.downloadEvents)
        .thenAnswer((_) => const Stream.empty());

    // ── PreferencesService ────────────────────────────────────────────────
    // LibraryScreen loads the persisted status filter during _initLibrary.
    when(mockPreferencesService.getStatusFilter()).thenAnswer((_) async => null);

    // ── DriveBookRepository ───────────────────────────────────────────────
    when(mockDriveBookRepository.getFilesForBook(any))
        .thenAnswer((_) async => []);

    // ── DriveLibraryService ───────────────────────────────────────────────
    // totalSizeBytes returns a known value (257,363,968 bytes ≈ 245.3 MB).
    when(mockDriveLibraryService.totalSizeBytes(any))
        .thenAnswer((_) async => 257363968);
    when(mockDriveLibraryService.startDownload(any))
        .thenAnswer((_) async {});
    when(mockDriveLibraryService.loadDriveBooks())
        .thenAnswer((_) async => [undownloadedDriveBook]);
    when(mockDriveLibraryService.driveBookDirs())
        .thenAnswer((_) async => <String>{});

    // ── EnrichmentService ─────────────────────────────────────────────────
    final coverController =
        StreamController<({String bookPath, String coverPath})>.broadcast();
    when(mockEnrichmentService.onCoverFetched)
        .thenAnswer((_) => coverController.stream);
    when(mockEnrichmentService.getAllEnrichedCovers())
        .thenAnswer((_) async => <String, String>{});
    when(mockEnrichmentService.enqueueBooks(any))
        .thenAnswer((_) async {});
    when(mockEnrichmentService.enrichingPaths)
        .thenReturn(ValueNotifier<Set<String>>(const {}));
    when(mockEnrichmentService.failedPaths)
        .thenReturn(ValueNotifier<Set<String>>(const {}));

    // ── PositionService ───────────────────────────────────────────────────
    when(mockPositionService.getAllPositions())
        .thenAnswer((_) async => <BookProgress>[]);
    when(mockPositionService.getAllStatuses())
        .thenAnswer((_) async => <String, BookStatus>{});
    when(mockPositionService.getLastPlayedBookPath())
        .thenAnswer((_) async => null);
    when(mockPositionService.getBookmarks(any))
        .thenAnswer((_) async => []);
    when(mockPositionService.getPosition(any))
        .thenAnswer((_) async => null);

    // ── PreferencesService ────────────────────────────────────────────────
    when(mockPreferencesService.getLibrarySort())
        .thenAnswer((_) async => null);
    when(mockPreferencesService.getLibraryPath())
        .thenAnswer((_) async => null); // no local folder
    when(mockPreferencesService.getDriveRootFolder())
        .thenAnswer((_) async => (id: 'root-id', name: 'AudioVault', isShared: false));
    when(mockPreferencesService.getMetadataEnrichment())
        .thenAnswer((_) async => false);
    when(mockPreferencesService.getRefreshOnStartup())
        .thenAnswer((_) async => false);
    when(mockPreferencesService.getAvailabilityFilter())
        .thenAnswer((_) async => AvailabilityFilterState.all);
    when(mockPreferencesService.getSkipInterval())
        .thenAnswer((_) async => 30);
    when(mockPreferencesService.getAutoRewind())
        .thenAnswer((_) async => false);

    // ── ScannerService ────────────────────────────────────────────────────
    when(mockScannerService.scanFolder(any,
            excludePaths: anyNamed('excludePaths'),
            onBookFound: anyNamed('onBookFound')))
        .thenAnswer((_) async => <Audiobook>[]);

    // ── SleepTimerController ──────────────────────────────────────────────
    when(mockSleepTimerController.remaining)
        .thenReturn(ValueNotifier<Duration?>(null));
    when(mockSleepTimerController.stopAtChapterEnd)
        .thenReturn(ValueNotifier<bool>(false));
    when(mockSleepTimerController.isActive).thenReturn(false);

    // ── KowhaiHandler ─────────────────────────────────────────────────
    // Using _FakeAudioHandler (not a mock) to avoid BehaviorSubject/when
    // interaction issues. The fake provides the minimal streams needed by
    // AudioHandlerScope-dependent widgets.
    // NOTE: _FakeAudioHandler constructor calls locator<PositionService>()
    // and locator<PreferencesService>(), so services must be registered first.
    fakeAudioHandler = _FakeAudioHandler();
  });

  tearDown(() async {
    locator.allowReassignment = true;
    for (final unregister in [
      () async {
        if (locator.isRegistered<DriveLibraryService>()) {
          await locator.unregister<DriveLibraryService>();
        }
      },
      () async {
        if (locator.isRegistered<DriveBookRepository>()) {
          await locator.unregister<DriveBookRepository>();
        }
      },
      () async {
        if (locator.isRegistered<DriveDownloadManager>()) {
          await locator.unregister<DriveDownloadManager>();
        }
      },
      () async {
        if (locator.isRegistered<EnrichmentService>()) {
          await locator.unregister<EnrichmentService>();
        }
      },
      () async {
        if (locator.isRegistered<PositionService>()) {
          await locator.unregister<PositionService>();
        }
      },
      () async {
        if (locator.isRegistered<PreferencesService>()) {
          await locator.unregister<PreferencesService>();
        }
      },
      () async {
        if (locator.isRegistered<ScannerService>()) {
          await locator.unregister<ScannerService>();
        }
      },
      () async {
        if (locator.isRegistered<SleepTimerController>()) {
          await locator.unregister<SleepTimerController>();
        }
      },
      () async {
        if (locator.isRegistered<DriveService>()) {
          await locator.unregister<DriveService>();
        }
      },
    ]) {
      await unregister();
    }
  });

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Wraps [child] in a MaterialApp with AudioHandlerScope so widgets that
  /// depend on AudioHandlerScope.of(context) work in tests.
  Widget wrapWithApp(Widget child) {
    return AudioHandlerScope(
      audioHandler: fakeAudioHandler,
      themeModeNotifier: ValueNotifier(ThemeMode.system),
      child: MaterialApp(
        home: child,
      ),
    );
  }

  /// Pumps [LibraryScreen] and waits for the initial scan to complete.
  /// The mock setup ensures `loadDriveBooks` returns [undownloadedDriveBook].
  Future<void> pumpLibraryScreen(WidgetTester tester) async {
    await tester.pumpWidget(wrapWithApp(const LibraryScreen()));
    // Allow the async _initLibrary + _scan to complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Taps the first visible book card with the given [title] in LibraryScreen.
  /// Scrolls to ensure the card is on-screen before tapping.
  Future<void> tapBookCard(WidgetTester tester, String title) async {
    final finder = find.text(title).first;
    // Scroll to ensure the card is visible in the viewport.
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    // _openPlayer is async (calls Connectivity().checkConnectivity() and
    // optionally totalSizeBytes), so we need to pump multiple frames to
    // allow the async work to complete and the bottom sheet to appear.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  /// Stubs the connectivity_plus platform channel to return [results].
  ///
  /// `connectivity_plus` uses the `dev.fluttercommunity.plus/connectivity`
  /// method channel. We stub `check` to return the encoded connectivity list
  /// so that `Connectivity().checkConnectivity()` returns [results] in tests.
  void stubConnectivity(List<ConnectivityResult> results) {
    // connectivity_plus encodes results as a list of strings.
    final encoded = results.map((r) => r.name).toList();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall call) async {
        if (call.method == 'check') {
          return encoded;
        }
        return null;
      },
    );
  }

  // ── Property 3: Preservation — Mobile Data Path Unchanged ─────────────────
  //
  // Requirements 3.1, 3.2, 3.6
  //
  // When the device is on mobile data, `_showDriveDownloadSheet` MUST continue
  // to show the mobile-data warning message with the formatted file size, and
  // the Download button label MUST include the formatted size.
  //
  // These tests tap an undownloaded Drive book card in LibraryScreen while
  // connectivity is stubbed to mobile data. The private `_showDriveDownloadSheet`
  // is exercised via the existing `_openPlayer` path (Requirement 3.6).
  //
  // Property: FOR ALL mobile-data connectivity states, the download sheet
  // shows the mobile-data warning message and annotated Download button label.

  group(
    'Property 3: Mobile-data path preserved (Requirements 3.1, 3.2, 3.6)',
    () {
      // The mobile-data connectivity states to test (property-based: multiple
      // representative values from the input space).
      const mobileConnectivityStates = [
        [ConnectivityResult.mobile],
        // mobile + wifi simultaneously (mobile data takes precedence for warning)
        [ConnectivityResult.mobile, ConnectivityResult.wifi],
      ];

      for (final connectivityState in mobileConnectivityStates) {
        final label = connectivityState.map((c) => c.name).join('+');

        testWidgets(
          'mobile-data sheet shows warning message with size '
          '(connectivity: $label)',
          (tester) async {
            // Stub the connectivity platform channel to return mobile data.
            // This ensures `_showDriveDownloadSheet` takes the mobile-data
            // branch (isWifi == false) and fetches totalSizeBytes.
            stubConnectivity(connectivityState);

            await pumpLibraryScreen(tester);

            // The undownloaded Drive book card should be visible.
            expect(
              find.text('Test Drive Book'),
              findsAtLeastNWidgets(1),
              reason: 'Expected the undownloaded Drive book card to be visible '
                  'in the library grid.',
            );

            // Tap the book card to trigger _openPlayer → _showDriveDownloadSheet.
            await tapBookCard(tester, 'Test Drive Book');

            // The download sheet MUST appear (Requirement 3.6).
            expect(
              find.byType(BottomSheet),
              findsOneWidget,
              reason:
                  'Expected the download bottom sheet to appear when tapping '
                  'an undownloaded Drive book card in the library grid '
                  '(Requirement 3.6). This is the existing _openPlayer path.',
            );

            // The sheet MUST contain a Cancel button.
            expect(
              find.text('Cancel'),
              findsOneWidget,
              reason: 'Expected a Cancel button in the download sheet.',
            );

            // The sheet MUST contain a Download button.
            expect(
              find.textContaining('Download'),
              findsAtLeastNWidgets(1),
              reason: 'Expected a Download button in the download sheet.',
            );
          },
        );
      }

      testWidgets(
        'mobile-data sheet shows formatted size in message and button label '
        '(direct connectivity stub via real mobile-data path)',
        (tester) async {
          // Stub connectivity as mobile data so the mobile-data branch is taken.
          stubConnectivity([ConnectivityResult.mobile]);

          await pumpLibraryScreen(tester);

          expect(find.text('Test Drive Book'), findsAtLeastNWidgets(1));

          await tapBookCard(tester, 'Test Drive Book');

          // Sheet must be shown.
          expect(find.byType(BottomSheet), findsOneWidget);

          // In the test environment (no network), Connectivity returns
          // ConnectivityResult.none → isWifi == false → mobile-data branch
          // is taken → totalSizeBytes IS called → size IS shown.
          //
          // Verify totalSizeBytes was called (confirms the fetch happened).
          verify(mockDriveLibraryService.totalSizeBytes('folder-123'))
              .called(greaterThanOrEqualTo(1));

          // The sheet MUST contain a formatted size string (Requirements 3.1, 3.2).
          expect(
            find.textContaining(RegExp(r'\d+(\.\d+)?\s*(B|KB|MB|GB)')),
            findsAtLeastNWidgets(1),
            reason:
                'Expected the bottom sheet to display a formatted file size '
                '(e.g. "245.3 MB") on mobile data. '
                'This confirms the mobile-data path is preserved (Req 3.1).',
          );

          // The Download button MUST include the formatted size (Requirement 3.2).
          expect(
            find.textContaining(
                RegExp(r'Download\s*\(\d+(\.\d+)?\s*(B|KB|MB|GB)\)')),
            findsOneWidget,
            reason:
                'Expected the Download button label to include the formatted '
                'file size (e.g. "Download (245.3 MB)") on mobile data. '
                'This confirms the mobile-data button label is preserved (Req 3.2).',
          );
        },
      );
    },
  );

  // ── Property 4: Preservation — Direct Navigation for Downloaded/Local Books ─
  //
  // Requirements 3.3, 3.4
  //
  // "Start listening" for a fully downloaded Drive book or a local book MUST
  // continue to navigate directly to PlayerScreen without showing the sheet.
  //
  // Property: FOR ALL fully-downloaded Drive books (audioFiles.length >= totalFileCount)
  // and FOR ALL local books, tapping "Start listening" pushes PlayerScreen
  // without showing a BottomSheet.

  group(
    'Property 4: Direct navigation preserved for downloaded/local books '
    '(Requirements 3.3, 3.4)',
    () {
      // ── Parameterized inputs for fully downloaded Drive books ─────────────
      //
      // Generate Drive books with varying audioFiles.length and totalFileCount
      // where fullyDownloaded == true (audioFiles.length >= totalFileCount > 0).
      final fullyDownloadedDriveBooks = [
        // Exactly at threshold: 1 file, totalFileCount = 1
        const Audiobook(
          title: 'Drive Book 1-of-1',
          path: '/drive/book-1-of-1',
          audioFiles: ['/local/file1.mp3'],
          source: AudiobookSource.drive,
          driveMetadata: DriveBookMeta(
            folderId: 'folder-1',
            folderName: 'Drive Book 1-of-1',
            isShared: false,
            totalFileCount: 1,
          ),
        ),
        // 3 files, totalFileCount = 3
        fullyDownloadedDriveBook,
        // 5 files, totalFileCount = 5
        const Audiobook(
          title: 'Drive Book 5-of-5',
          path: '/drive/book-5-of-5',
          audioFiles: [
            '/local/f1.mp3',
            '/local/f2.mp3',
            '/local/f3.mp3',
            '/local/f4.mp3',
            '/local/f5.mp3',
          ],
          source: AudiobookSource.drive,
          driveMetadata: DriveBookMeta(
            folderId: 'folder-5',
            folderName: 'Drive Book 5-of-5',
            isShared: false,
            totalFileCount: 5,
          ),
        ),
        // More files than totalFileCount (edge case: over-downloaded)
        const Audiobook(
          title: 'Drive Book Over',
          path: '/drive/book-over',
          audioFiles: ['/local/f1.mp3', '/local/f2.mp3'],
          source: AudiobookSource.drive,
          driveMetadata: DriveBookMeta(
            folderId: 'folder-over',
            folderName: 'Drive Book Over',
            isShared: false,
            totalFileCount: 1,
          ),
        ),
      ];

      for (final book in fullyDownloadedDriveBooks) {
        final downloaded = book.audioFiles.length;
        final total = book.driveMetadata?.totalFileCount ?? 0;

        testWidgets(
          '"Start listening" navigates to PlayerScreen for fully downloaded '
          'Drive book (audioFiles=$downloaded, totalFileCount=$total) '
          '(Requirement 3.3)',
          (tester) async {
            await tester.pumpWidget(wrapWithApp(
              BookDetailsScreen(book: book),
            ));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));

            final startListeningButton = find.text('Start listening');
            expect(startListeningButton, findsOneWidget,
                reason: 'Could not find the "Start listening" button.');

            await tester.tap(startListeningButton);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));

            // PRESERVED behavior: PlayerScreen IS pushed.
            expect(
              find.byType(PlayerScreen),
              findsOneWidget,
              reason:
                  'Expected PlayerScreen to be pushed when tapping "Start '
                  'listening" on a fully downloaded Drive book '
                  '(audioFiles=$downloaded, totalFileCount=$total). '
                  'This is the preserved behavior (Requirement 3.3).',
            );

            // PRESERVED behavior: no download sheet is shown.
            expect(
              find.byType(BottomSheet),
              findsNothing,
              reason:
                  'Expected NO download bottom sheet when tapping "Start '
                  'listening" on a fully downloaded Drive book. '
                  'This is the preserved behavior (Requirement 3.3).',
            );
          },
        );
      }

      // ── Parameterized inputs for local books ──────────────────────────────
      //
      // Generate local books with varying audioFiles.length.
      final localBooks = [
        // Single-file local book
        localBook,
        // Multi-file local book
        const Audiobook(
          title: 'Local Multi-File Book',
          path: '/local/multi-file',
          audioFiles: [
            '/local/multi-file/ch1.mp3',
            '/local/multi-file/ch2.mp3',
            '/local/multi-file/ch3.mp3',
          ],
          source: AudiobookSource.local,
        ),
        // Local book with many files
        Audiobook(
          title: 'Local Large Book',
          path: '/local/large-book',
          audioFiles: List.generate(10, (i) => '/local/large-book/ch$i.mp3'),
          source: AudiobookSource.local,
        ),
      ];

      for (final book in localBooks) {
        testWidgets(
          '"Start listening" navigates to PlayerScreen for local book '
          '"${book.title}" (audioFiles=${book.audioFiles.length}) '
          '(Requirement 3.4)',
          (tester) async {
            await tester.pumpWidget(wrapWithApp(
              BookDetailsScreen(book: book),
            ));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));

            final startListeningButton = find.text('Start listening');
            expect(startListeningButton, findsOneWidget,
                reason: 'Could not find the "Start listening" button.');

            await tester.tap(startListeningButton);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));

            // PRESERVED behavior: PlayerScreen IS pushed.
            expect(
              find.byType(PlayerScreen),
              findsOneWidget,
              reason:
                  'Expected PlayerScreen to be pushed when tapping "Start '
                  'listening" on a local book "${book.title}". '
                  'This is the preserved behavior (Requirement 3.4).',
            );

            // PRESERVED behavior: no download sheet is shown.
            expect(
              find.byType(BottomSheet),
              findsNothing,
              reason:
                  'Expected NO download bottom sheet when tapping "Start '
                  'listening" on a local book. '
                  'This is the preserved behavior (Requirement 3.4).',
            );
          },
        );
      }
    },
  );

  // ── Property 5: Consistency — "Download to device" shows download sheet ─────
  //
  // Requirement 3.5 (updated)
  //
  // Tapping the "Download to device" OutlinedButton for an undownloaded Drive
  // book MUST show the download prompt sheet (same as tapping the book from
  // the library) so the user sees the size and mobile-data warning.

  group(
    'Property 5: "Download to device" shows download sheet (Requirement 3.5)',
    () {
      testWidgets(
        '"Download to device" shows the download sheet '
        '(Requirement 3.5)',
        (tester) async {
          // Stub totalSizeBytes so the download sheet can display the size.
          when(mockDriveLibraryService.totalSizeBytes('folder-123'))
              .thenAnswer((_) async => 100000000);

          await tester.pumpWidget(wrapWithApp(
            BookDetailsScreen(book: undownloadedDriveBook),
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // The "Download to device" OutlinedButton should be visible.
          final downloadButton = find.text('Download to device');
          expect(downloadButton, findsOneWidget,
              reason:
                  'Could not find the "Download to device" button for an '
                  'undownloaded Drive book.');

          await tester.tap(downloadButton);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // UPDATED behavior: download sheet IS shown (consistent with
          // tapping the book from the library).
          expect(
            find.byType(BottomSheet),
            findsOneWidget,
            reason:
                'Expected the download bottom sheet when tapping "Download to '
                'device". The button should show the prompt with size and '
                'connectivity info (Requirement 3.5).',
          );

          // startDownload should NOT have been called yet — user hasn't
          // confirmed in the sheet.
          verifyNever(mockDriveLibraryService.startDownload('folder-123'));
        },
      );
    },
  );

  // ── Property 6: Gating — "Start listening" respects download state ──────────
  //
  // Requirement 1.2
  //
  // Tapping "Start listening" on an UNDOWNLOADED Drive book MUST show the
  // download prompt sheet instead of navigating to PlayerScreen. Ported from
  // the retired exploration suite ("Bug B") so the regression coverage lives
  // in this durable file rather than a scratch artifact.

  group(
    'Property 6: "Start listening" gates undownloaded books (Requirement 1.2)',
    () {
      testWidgets(
        '"Start listening" shows download sheet (not PlayerScreen) for '
        'undownloaded Drive book',
        (tester) async {
          stubConnectivity([ConnectivityResult.wifi]);

          await tester.pumpWidget(wrapWithApp(
            BookDetailsScreen(book: undownloadedDriveBook),
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final startListeningButton = find.text('Start listening');
          expect(startListeningButton, findsOneWidget,
              reason: 'Could not find the "Start listening" button.');

          await tester.tap(startListeningButton);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump(const Duration(milliseconds: 200));

          // PlayerScreen must NOT be pushed.
          expect(
            find.byType(PlayerScreen),
            findsNothing,
            reason:
                'Expected PlayerScreen NOT to be pushed when tapping '
                '"Start listening" on an undownloaded Drive book.',
          );

          // The download sheet MUST be shown instead.
          expect(
            find.byType(BottomSheet),
            findsOneWidget,
            reason:
                'Expected the download bottom sheet when tapping '
                '"Start listening" on an undownloaded Drive book.',
          );

          // Download must not begin without user confirmation.
          verifyNever(mockDriveLibraryService.startDownload('folder-123'));
        },
      );
    },
  );
}
