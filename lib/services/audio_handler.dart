import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/audiobook.dart';
import 'cast_controller.dart';
import 'drive_library_service.dart';
import 'drive_removal_scheduler.dart';
import 'position_persister.dart' as pp;
import 'position_service.dart';
import 'preferences_service.dart';
import '../locator.dart';

class AudioVaultHandler extends BaseAudioHandler {
  final _player = AudioPlayer();
  Audiobook? _book;
  Uri? _artUri;
  late final pp.PositionPersister _persister;
  late final DriveRemovalScheduler _driveRemoval;
  DateTime? _lastPausedAt;

  AudioPlayer get player => _player;
  Audiobook? get currentBook => _book;

  // ── Cast state ──────────────────────────────────────────────────────────────

  late final CastController _cast;
  bool get isCasting => _cast.isCasting;
  Stream<bool> get castingStream => _cast.castingStream;

  int _skipInterval = 30;

  /// Effective position stream — emits local or Cast position depending on mode.
  final _effectivePositionController = StreamController<Duration>.broadcast();
  Stream<Duration> get effectivePositionStream =>
      _effectivePositionController.stream;

  /// Effective duration — updated when media loads locally or on Cast.
  final _effectiveDurationController = StreamController<Duration?>.broadcast();
  Stream<Duration?> get effectiveDurationStream =>
      _effectiveDurationController.stream;

  AudioVaultHandler() {
    _persister = pp.PositionPersister(
      positionService: locator<PositionService>(),
      getBook: () => _book,
      readPosition: () => (
        chapterIndex: _player.currentIndex ?? 0,
        position: isCasting ? _cast.position : _player.position,
      ),
    );

    _driveRemoval = DriveRemovalScheduler(
      getBookStatus: (p) => locator<PositionService>().getBookStatus(p),
      deleteFiles: (f) => locator<DriveLibraryService>().deleteLocalFiles(f),
      isRemoveWhenFinishedEnabled: () =>
          locator<PreferencesService>().getRemoveWhenFinished(),
    );

    _cast = CastController(
      localPlayer: _player,
      persister: _persister,
      getBook: () => _book,
      onEffectivePosition: (p) => _effectivePositionController.add(p),
      onEffectiveDuration: (d) => _effectiveDurationController.add(d),
      onStatusChanged: _onCastStatusChanged,
    );

    locator<PreferencesService>().getSkipInterval().then((s) {
      _skipInterval = s;
    });

    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e) {
        debugPrint('[AudioVault:Error] playback error: $e');
      },
    );

    _player.playingStream.listen((playing) {
      if (!playing) {
        _lastPausedAt ??= DateTime.now();
      } else {
        _lastPausedAt = null;
      }
    });
    _player.currentIndexStream.listen(
      (index) {
        _broadcastState(null);
      },
      onError: (error, stackTrace) {
        debugPrint('[AudioVault:Player] Index stream error: $error');
      },
    );

    // Forward local streams to effective streams when not casting.
    _player.positionStream.listen((pos) {
      if (!isCasting) _effectivePositionController.add(pos);
    });
    _player.durationStream.listen((dur) {
      if (!isCasting) _effectiveDurationController.add(dur);
    });

    // Start/stop periodic save as playback state changes.
    _player.playingStream.listen((playing) {
      if (isCasting) return; // Cast save is handled separately.
      if (playing) {
        _persister.startPeriodic();
      } else {
        _persister.stopPeriodic();
        _persister.save(); // immediate save on pause
      }
    });

    // Handle playback completion (end of last file / M4B).
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _persister.save();
        _onPlaybackCompleted();
      }
    });

    // Listen for Cast session changes.
    _cast.listenForSessions();
  }

  // ── Cast status → notification state ─────────────────────────────────────

  /// Invoked by [CastController] whenever the receiver reports a new status.
  /// Translates it into the platform notification state + media item.
  void _onCastStatusChanged(GoggleCastMediaStatus status) {
    final mapped = mapCastPlayerState(status.playerState);
    final castPosition = _cast.position;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        _rewindControl,
        MediaControl.skipToPrevious,
        mapped.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        _forwardControl,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [1, 2, 3],
      processingState: mapped.processingState,
      playing: mapped.playing,
      updatePosition: castPosition,
      speed: status.playbackRate.toDouble(),
    ));

    final dur = status.mediaInformation?.duration;
    if (dur != null) _effectiveDurationController.add(dur);

    if (_book != null) _updateMediaItem();
  }

  // ── Completion handling ────────────────────────────────────────────────────

  Future<void> _onPlaybackCompleted() async {
    final book = _book;
    if (book == null) return;
    await locator<PositionService>()
        .updateBookStatus(book.path, BookStatus.finished);
    await _driveRemoval.scheduleForBook(book);
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> loadBook(Audiobook book) async {
    if (_book?.path == book.path) return; // already loaded — resume in place
    _book = book;

    // Resolve artwork URI for the notification.
    _artUri = null;
    if (book.coverImagePath != null) {
      _artUri = Uri.file(book.coverImagePath!);
    } else if (book.coverImageBytes != null) {
      try {
        final tmp = await getTemporaryDirectory();
        final f = File('${tmp.path}/sbcover_${book.path.hashCode.abs()}.jpg');
        if (!await f.exists()) await f.writeAsBytes(book.coverImageBytes!);
        _artUri = f.uri;
      } catch (_) {}
    }

    // Restore saved position, or start from beginning.
    final saved = await locator<PositionService>().getPosition(book.path);

    final sources =
        book.audioFiles.map((p) => AudioSource.uri(Uri.file(p))).toList();
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: saved?.chapterIndex ?? 0,
        initialPosition: saved?.position,
      );
    } catch (e) {
      _book = null;
      _artUri = null;
      rethrow;
    }
    _updateMediaItem();

    // If already casting, re-cast the new book.
    if (isCasting) {
      await _cast.stop();
      if (_cast.isSessionConnected) await _cast.start();
    }
  }

  // ── Position persistence ───────────────────────────────────────────────────

  /// Kept as a redirect for existing tests; real implementation is in
  /// `position_persister.dart`.
  @visibleForTesting
  static int calculateGlobalPosition({
    required int chapterIndex,
    required Duration chapterPosition,
    required List<Duration> chapterDurations,
  }) =>
      pp.calculateGlobalPosition(
        chapterIndex: chapterIndex,
        chapterPosition: chapterPosition,
        chapterDurations: chapterDurations,
      );

  @visibleForTesting
  static Duration getRewindOffset(Duration pausedDuration) {
    if (pausedDuration >= const Duration(hours: 24)) {
      return const Duration(seconds: 30);
    } else if (pausedDuration >= const Duration(hours: 1)) {
      return const Duration(seconds: 15);
    } else if (pausedDuration >= const Duration(minutes: 5)) {
      return const Duration(seconds: 10);
    }
    return Duration.zero;
  }

  // ── Playback controls ──────────────────────────────────────────────────────

  @override
  Future<void> play() async {
    // Cancel any pending removal — user is resuming/restarting.
    _driveRemoval.cancel();

    // If the book was finished and the user explicitly plays again, reset to inProgress.
    if (_book != null) {
      final status = await locator<PositionService>().getBookStatus(_book!.path);
      if (status == BookStatus.finished) {
        await locator<PositionService>()
            .updateBookStatus(_book!.path, BookStatus.inProgress);
      }
    }

    final autoRewind = await locator<PreferencesService>().getAutoRewind();
    if (autoRewind && _lastPausedAt != null) {
      final pausedDuration = DateTime.now().difference(_lastPausedAt!);
      final rewindAmount = getRewindOffset(pausedDuration);
      if (rewindAmount > Duration.zero) {
        final currentPos = isCasting ? _cast.position : _player.position;
        var newPos = currentPos - rewindAmount;
        if (newPos < Duration.zero) newPos = Duration.zero;
        await seek(newPos);
      }
    }
    _lastPausedAt = null;

    if (isCasting) {
      await _cast.play();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    _lastPausedAt = DateTime.now();
    if (isCasting) {
      await _cast.pause();
      _persister.save();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (isCasting) {
      await _cast.seekAbsolute(position);
    } else {
      await _player.seek(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (isCasting) {
      final chapters = _book?.chapters;
      if (chapters != null && chapters.isNotEmpty) {
        final idx = _book!.chapterIndexAt(_cast.position);
        if (idx < chapters.length - 1) {
          await seek(chapters[idx + 1].start);
        }
      } else {
        await _cast.queueNext();
      }
      return;
    }

    final chapters = _book?.chapters;
    if (chapters != null && chapters.isNotEmpty) {
      final idx = _book!.chapterIndexAt(_player.position);
      if (idx < chapters.length - 1) {
        await _player.seek(chapters[idx + 1].start);
      }
      return;
    }
    final idx = _player.currentIndex ?? 0;
    final len = _player.sequence.length;
    if (idx < len - 1) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (isCasting) {
      final chapters = _book?.chapters;
      if (chapters != null && chapters.isNotEmpty) {
        final pos = _cast.position;
        final idx = _book!.chapterIndexAt(pos);
        final chapterStart = chapters[idx].start;
        if (pos - chapterStart > const Duration(seconds: 5)) {
          await seek(chapterStart);
        } else if (idx > 0) {
          await seek(chapters[idx - 1].start);
        } else {
          await seek(Duration.zero);
        }
      } else {
        await _cast.queuePrev();
      }
      return;
    }

    final chapters = _book?.chapters;
    if (chapters != null && chapters.isNotEmpty) {
      final idx = _book!.chapterIndexAt(_player.position);
      final chapterStart = chapters[idx].start;
      if (_player.position - chapterStart > const Duration(seconds: 5)) {
        await _player.seek(chapterStart);
      } else if (idx > 0) {
        await _player.seek(chapters[idx - 1].start);
      } else {
        await _player.seek(Duration.zero);
      }
      return;
    }
    if (_player.position > const Duration(seconds: 5)) {
      await _player.seek(Duration.zero);
    } else {
      final idx = _player.currentIndex ?? 0;
      if (idx > 0) {
        await _player.seekToPrevious();
      } else {
        await _player.seek(Duration.zero);
      }
    }
  }

  @override
  Future<void> fastForward() async {
    final secs = await locator<PreferencesService>().getSkipInterval();
    final interval = Duration(seconds: secs);
    if (isCasting) {
      await _cast.seekRelative(interval);
      return;
    }
    final dur = _player.duration ?? Duration.zero;
    final pos = _player.position + interval;
    await _player.seek(pos > dur ? dur : pos);
  }

  @override
  Future<void> rewind() async {
    final secs = await locator<PreferencesService>().getSkipInterval();
    final interval = Duration(seconds: secs);
    if (isCasting) {
      await _cast.seekRelative(Duration(seconds: -secs));
      return;
    }
    final pos = _player.position - interval;
    await _player.seek(pos < Duration.zero ? Duration.zero : pos);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (isCasting) {
      await _cast.setSpeed(speed);
    }
    // Always set local speed too so it's remembered.
    await _player.setSpeed(speed);
  }

  @override
  Future<void> stop() async {
    if (isCasting) {
      await _persister.save();
      await _cast.stopClient();
    }
    await _persister.save();
    await _player.stop();
    return super.stop();
  }

  // ── State broadcasting ─────────────────────────────────────────────────────

  void updateSkipInterval(int seconds) {
    _skipInterval = seconds;
    _broadcastState(null);
  }

  MediaControl get _rewindControl => MediaControl(
    androidIcon: 'drawable/ic_replay',
    label: '-$_skipInterval s',
    action: MediaAction.rewind,
  );

  MediaControl get _forwardControl => MediaControl(
    androidIcon: 'drawable/ic_forward',
    label: '+$_skipInterval s',
    action: MediaAction.fastForward,
  );

  void _broadcastState(PlaybackEvent? event) {
    if (isCasting) return; // Cast status drives the broadcast when casting.

    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        _rewindControl,
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        _forwardControl,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [1, 2, 3],
      processingState: {
        ProcessingState.idle:      AudioProcessingState.idle,
        ProcessingState.loading:   AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready:     AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    ));

    if (_player.duration != null) _updateMediaItem();
  }

  void _updateMediaItem() {
    if (_book == null) return;
    final idx = _player.currentIndex ?? 0;
    mediaItem.add(MediaItem(
      id: _book!.path,
      title: _book!.title,
      artist: _book!.author ?? '',
      duration: _player.duration,
      artUri: _artUri,
      extras: {
        'chapterIndex': idx,
        'chapterCount': _book!.chapters.isNotEmpty
            ? _book!.chapters.length
            : _book!.audioFiles.length,
      },
    ));
  }
}
