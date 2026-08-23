import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kowhai/locator.dart';
import 'package:kowhai/models/audiobook.dart';
import 'package:kowhai/services/audio_handler.dart';
import 'package:kowhai/services/cast_controller.dart';
import 'package:kowhai/services/position_persister.dart';
import 'package:kowhai/services/position_service.dart';
import 'package:kowhai/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_handler_test.mocks.dart' show MockAudioPlayer;

/// Records call order and lets tests flip casting state. Implements (not
/// extends) CastController so no SDK statics are ever reached and no base
/// constructor runs.
class FakeCastController implements CastController {
  FakeCastController(this.localPlayer, this.persister);

  @override
  final AudioPlayer localPlayer;
  @override
  final PositionPersister persister;

  bool casting = false;
  bool sessionStaysConnected = true;
  final List<String> calls = [];

  @override
  bool get isCasting => casting;

  @override
  bool get isSessionConnected => sessionStaysConnected;

  @override
  Future<void> start() async {
    calls.add('start');
    casting = true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    casting = false;
  }

  @override
  void listenForSessions() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Audiobook _book(String path) => Audiobook(
      title: path,
      path: path,
      audioFiles: ['$path/file.mp3'],
      chapterDurations: const [Duration(minutes: 10)],
      duration: const Duration(minutes: 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late PositionService positionService;
  late MockAudioPlayer mockPlayer;
  late FakeCastController fakeCast;
  late KowhaiHandler handler;
  late int saveCount;

  final setAudioSourcesCalls =
      <({int? initialIndex, Duration? initialPosition})>[];
  final positionController = StreamController<Duration>.broadcast();
  final playingController = StreamController<bool>.broadcast();
  final indexController = StreamController<int?>.broadcast();
  final durationController = StreamController<Duration?>.broadcast();
  final processingController = StreamController<ProcessingState>.broadcast();
  final playbackEventController = StreamController<PlaybackEvent>.broadcast();

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    saveCount = 0;
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE positions (
            book_path TEXT PRIMARY KEY,
            chapter_index INTEGER NOT NULL DEFAULT 0,
            position_ms INTEGER NOT NULL DEFAULT 0,
            global_position_ms INTEGER NOT NULL DEFAULT 0,
            total_duration_ms INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            status TEXT
          )
        '''),
      ),
    );
    positionService =
        PositionService.withDatabase(db, onPositionSaved: () => saveCount++);

    SharedPreferences.setMockInitialValues({});
    setupLocator();
    locator.allowReassignment = true;
    locator.registerLazySingleton<PositionService>(() => positionService);
    locator.registerLazySingleton<PreferencesService>(() => PreferencesService());

    mockPlayer = MockAudioPlayer();
    setAudioSourcesCalls.clear();

    // Streams the handler subscribes to in its constructor.
    when(mockPlayer.playbackEventStream)
        .thenAnswer((_) => playbackEventController.stream);
    when(mockPlayer.playingStream).thenAnswer((_) => playingController.stream);
    when(mockPlayer.currentIndexStream)
        .thenAnswer((_) => indexController.stream);
    when(mockPlayer.durationStream).thenAnswer((_) => durationController.stream);
    when(mockPlayer.processingStateStream)
        .thenAnswer((_) => processingController.stream);
    when(mockPlayer.positionStream).thenAnswer((_) => positionController.stream);

    when(mockPlayer.position).thenReturn(Duration.zero);
    when(mockPlayer.currentIndex).thenReturn(0);
    when(mockPlayer.speed).thenReturn(1.0);
    when(mockPlayer.playing).thenReturn(false);
    when(mockPlayer.duration).thenReturn(null);
    when(mockPlayer.bufferedPosition).thenReturn(Duration.zero);
    when(mockPlayer.processingState).thenReturn(ProcessingState.idle);

    when(mockPlayer.setAudioSources(any,
            initialIndex: anyNamed('initialIndex'),
            initialPosition: anyNamed('initialPosition')))
        .thenAnswer((invocation) async {
      setAudioSourcesCalls.add((
        initialIndex: invocation.namedArguments[#initialIndex] as int?,
        initialPosition:
            invocation.namedArguments[#initialPosition] as Duration?,
      ));
      return Duration.zero;
    });
    when(mockPlayer.stop()).thenAnswer((_) async {});
    when(mockPlayer.pause()).thenAnswer((_) async {});

    fakeCast = FakeCastController(
      mockPlayer,
      PositionPersister(
        positionService: positionService,
        readPosition: () => null,
        getBook: () => null,
      ),
    );

    handler = KowhaiHandler(player: mockPlayer, cast: fakeCast);
  });

  tearDown(() async {
    await locator.reset();
  });

  group('KowhaiHandler lifecycle', () {
    test('loadBook restores the saved chapter and offset', () async {
      await positionService.savePosition(
        bookPath: '/books/a',
        chapterIndex: 3,
        position: const Duration(minutes: 2),
        globalPositionMs: 1920000,
        totalDurationMs: 6000000,
      );

      await handler.loadBook(_book('/books/a'));

      expect(setAudioSourcesCalls, hasLength(1));
      expect(setAudioSourcesCalls.single.initialIndex, 3);
      expect(setAudioSourcesCalls.single.initialPosition,
          const Duration(minutes: 2));
      expect(handler.currentBook!.path, '/books/a');
    });

    test('loadBook failure keeps the previous book current and reports error',
        () async {
      await handler.loadBook(_book('/books/first'));
      expect(handler.currentBook!.path, '/books/first');
      fakeCast.calls.clear();
      // The failure test concerns local loads only.
      fakeCast.sessionStaysConnected = false;

      when(mockPlayer.setAudioSources(any,
              initialIndex: anyNamed('initialIndex'),
              initialPosition: anyNamed('initialPosition')))
          .thenThrow(Exception('source error'));

      await expectLater(
          handler.loadBook(_book('/books/broken')), throwsException);
      expect(handler.currentBook!.path, '/books/first',
          reason: 'a failed load must not null out the current book');
      expect(handler.lastError, isNotNull);
      expect(fakeCast.calls.where((c) => c == 'start'), isEmpty,
          reason: 'no re-cast attempt after a failed load');

      // Restore the happy stub for later tests' teardown sanity.
      when(mockPlayer.setAudioSources(any,
              initialIndex: anyNamed('initialIndex'),
              initialPosition: anyNamed('initialPosition')))
          .thenAnswer((invocation) async {
        setAudioSourcesCalls.add((
          initialIndex: invocation.namedArguments[#initialIndex] as int?,
          initialPosition:
              invocation.namedArguments[#initialPosition] as Duration?,
        ));
        return Duration.zero;
      });
    });

    test('persister save during load is suppressed (no cross-book write)',
        () async {
      // Book A already current.
      await handler.loadBook(_book('/books/old'));
      final savesAfterLoad = saveCount;
      expect(savesAfterLoad, 0);

      // Local load — the connected-cast re-cast path is out of scope here.
      fakeCast.sessionStaysConnected = false;

      final gate = Completer<void>();
      when(mockPlayer.setAudioSources(any,
              initialIndex: anyNamed('initialIndex'),
              initialPosition: anyNamed('initialPosition')))
          .thenAnswer((_) async {
        await gate.future;
        return Duration.zero;
      });

      final loading = handler.loadBook(_book('/books/new'));
      await Future.delayed(Duration.zero); // let the load enter _loading

      // What would be a periodic tick mid-swap: must be suppressed.
      await handler.persister.save();
      expect(saveCount, savesAfterLoad,
          reason: 'mid-load sampling could persist one book under another '
              "path — it must be suppressed");

      gate.complete();
      await loading;

      // Post-load saves are allowed again and target the new book.
      when(mockPlayer.position).thenReturn(const Duration(seconds: 9));
      when(mockPlayer.currentIndex).thenReturn(0);
      await handler.persister.save();
      expect(saveCount, greaterThan(savesAfterLoad));
      final row = (await positionService.getAllPositions())
          .firstWhere((r) => r.bookPath == '/books/new');
      expect(row.positionMs, const Duration(seconds: 9).inMilliseconds);
    });

    test('switching books while casting stops cast before swapping sources',
        () async {
      fakeCast.casting = true; // pretend a cast session is live

      await handler.loadBook(_book('/books/second'));

      expect(fakeCast.calls.first, 'stop',
          reason: 'teardown must precede the source swap so its seek-back '
              'applies to the old book audio');
      expect(setAudioSourcesCalls, hasLength(1));
      expect(fakeCast.calls, contains('start'));
      expect(fakeCast.calls.indexOf('stop'),
          lessThan(fakeCast.calls.indexOf('start')));
    });

    test('stop() delegates to cast teardown without a second local save',
        () async {
      fakeCast.casting = true;
      await handler.loadBook(_book('/books/cast-book'));

      await handler.stop();

      expect(fakeCast.casting, isFalse,
          reason: 'handler stop must tear the cast session down');
      expect(saveCount, 0,
          reason: 'while casting, the cast owns the final save — the local '
              'persister must not double-save');
    });
  });
}
