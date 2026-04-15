import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/audiobook.dart';
import 'cast_server.dart';
import 'position_service.dart';
import 'preferences_service.dart';
import 'telemetry_service.dart';
import '../locator.dart';

class AudioVaultHandler extends BaseAudioHandler {
  final _player = AudioPlayer();
  Audiobook? _book;
  Uri? _artUri;
  Timer? _saveTimer;
  DateTime? _lastPausedAt;
  Timer? _removalTimer; // 1-min delay before deleting Drive files on finish

  AudioPlayer get player => _player;
  Audiobook? get currentBook => _book;

  // ── Cast state ──────────────────────────────────────────────────────────────

  bool _casting = false;
  bool get isCasting => _casting;

  int _skipInterval = 30;

  final _castingController = StreamController<bool>.broadcast();
  Stream<bool> get castingStream => _castingController.stream;

  final CastServer _castServer = CastServer();
  String? _castBaseUrl;

  StreamSubscription? _castSessionSub;
  StreamSubscription? _castStatusSub;
  StreamSubscription? _castPositionSub;

  /// Effective position stream — emits local or Cast position depending on mode.
  final _effectivePositionController = StreamController<Duration>.broadcast();
  Stream<Duration> get effectivePositionStream =>
      _effectivePositionController.stream;

  /// Effective duration — updated when media loads locally or on Cast.
  final _effectiveDurationController = StreamController<Duration?>.broadcast();
  Stream<Duration?> get effectiveDurationStream =>
      _effectiveDurationController.stream;

  AudioVaultHandler() {
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
      if (!_casting) _effectivePositionController.add(pos);
    });
    _player.durationStream.listen((dur) {
      if (!_casting) _effectiveDurationController.add(dur);
    });

    // Start/stop periodic save as playback state changes.
    _player.playingStream.listen((playing) {
      if (_casting) return; // Cast save is handled separately.
      if (playing) {
        _saveTimer ??= Timer.periodic(
            const Duration(seconds: 5), (_) => _savePosition());
      } else {
        _saveTimer?.cancel();
        _saveTimer = null;
        _savePosition(); // immediate save on pause
      }
    });

    // Handle playback completion (end of last file / M4B).
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _savePosition();
        _onPlaybackCompleted();
      }
    });

    // Listen for Cast session changes.
    _initCastListener();
  }

  // ── Cast session listener ─────────────────────────────────────────────────

  void _initCastListener() {
    _castSessionSub = GoogleCastSessionManager
        .instance.currentSessionStream
        .listen((_) {
      final connected =
          GoogleCastSessionManager.instance.connectionState ==
          GoogleCastConnectState.connected;
      if (connected && !_casting) {
        _startCasting();
      } else if (!connected && _casting) {
        _stopCasting();
      }
    });
  }

  Future<void> _startCasting() async {
    if (_book == null) return;

    _casting = true;
    _castingController.add(true);

    final wasPlaying = _player.playing;
    final position = _player.position;
    final currentIndex = _player.currentIndex ?? 0;
    final speed = _player.speed;

    // Pause local player — Cast device takes over.
    await _player.pause();

    // Start HTTP server.
    try {
      _castBaseUrl = await _castServer.start(
        _book!.audioFiles,
        coverPath: _book!.coverImagePath,
      );
    } catch (e) {
      debugPrint('[AudioVault:Cast] Failed to start server: $e');
      _casting = false;
      _castingController.add(false);
      if (wasPlaying) _player.play();
      return;
    }

    // Build cover URL if available.
    Uri? coverUrl;
    if (_book!.coverImagePath != null) {
      coverUrl = Uri.parse('$_castBaseUrl/cover');
    }

    final client = GoogleCastRemoteMediaClient.instance;

    // Listen to Cast status and position for UI + state broadcasting.
    _castStatusSub = client.mediaStatusStream.listen(_onCastStatusChanged);
    _castPositionSub = client.playerPositionStream.listen((pos) {
      _effectivePositionController.add(pos);
    });

    // Start periodic position save during Cast playback.
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _saveCastPosition());

    try {
      if (_book!.audioFiles.length == 1) {
        // Single file (M4B or single MP3).
        await client.loadMedia(
          GoogleCastMediaInformation(
            contentId: _book!.path,
            streamType: CastMediaStreamType.buffered,
            contentUrl: Uri.parse('$_castBaseUrl/audio/0'),
            contentType: _castMimeType(_book!.audioFiles[0]),
            metadata: GoogleCastMusicMediaMetadata(
              title: _book!.title,
              artist: _book!.author,
              images: coverUrl != null
                  ? [GoogleCastImage(url: coverUrl)]
                  : null,
            ),
            duration: _book!.duration,
          ),
          autoPlay: wasPlaying,
          playPosition: position,
          playbackRate: speed,
        );
        // Emit the full-file duration for the UI slider.
        _effectiveDurationController.add(_book!.duration);
      } else {
        // Multi-file: load as a queue.
        final items = _book!.audioFiles.asMap().entries.map((e) {
          return GoogleCastQueueItem(
            mediaInformation: GoogleCastMediaInformation(
              contentId: '${_book!.path}/${e.key}',
              streamType: CastMediaStreamType.buffered,
              contentUrl: Uri.parse('$_castBaseUrl/audio/${e.key}'),
              contentType: _castMimeType(e.value),
              metadata: GoogleCastMusicMediaMetadata(
                title: _book!.title,
                artist: _book!.author,
                images: coverUrl != null
                    ? [GoogleCastImage(url: coverUrl)]
                    : null,
              ),
              duration: e.key < _book!.chapterDurations.length
                  ? _book!.chapterDurations[e.key]
                  : null,
            ),
          );
        }).toList();

        await client.queueLoadItems(
          items,
          options: GoogleCastQueueLoadOptions(
            startIndex: currentIndex,
            playPosition: position,
          ),
        );
        if (wasPlaying) await client.play();
        await client.setPlaybackRate(speed);
        // Emit the current chapter's duration.
        if (currentIndex < _book!.chapterDurations.length) {
          _effectiveDurationController
              .add(_book!.chapterDurations[currentIndex]);
        }
      }
      TelemetryService.logEvent('cast_start', parameters: {
        'file_count': _book!.audioFiles.length,
      });
    } catch (e) {
      debugPrint('[AudioVault:Cast] Failed to load media on Cast: $e');
      // Fall back to local playback.
      _casting = false;
      _castingController.add(false);
      _castStatusSub?.cancel();
      _castPositionSub?.cancel();
      _saveTimer?.cancel();
      _saveTimer = null;
      await _castServer.stop();
      if (wasPlaying) _player.play();
    }
  }

  Future<void> _stopCasting() async {
    if (!_casting) return;

    // Grab Cast position before tearing down.
    Duration castPosition = Duration.zero;
    try {
      castPosition =
          GoogleCastRemoteMediaClient.instance.playerPosition;
    } catch (_) {}

    _castStatusSub?.cancel();
    _castPositionSub?.cancel();
    _saveTimer?.cancel();
    _saveTimer = null;
    _castStatusSub = null;
    _castPositionSub = null;

    await _castServer.stop();

    TelemetryService.logEvent('cast_stop');

    _casting = false;
    _castingController.add(false);

    // Resume local playback at the Cast position.
    if (_book != null) {
      await _player.seek(castPosition);
      // Re-broadcast local streams.
      _effectivePositionController.add(_player.position);
      _effectiveDurationController.add(_player.duration);
    }
  }

  void _onCastStatusChanged(GoggleCastMediaStatus? status) {
    if (status == null) return;

    // Map Cast player state to audio_service state for notification controls.
    final AudioProcessingState processingState;
    final bool playing;

    switch (status.playerState) {
      case CastMediaPlayerState.playing:
        processingState = AudioProcessingState.ready;
        playing = true;
      case CastMediaPlayerState.paused:
        processingState = AudioProcessingState.ready;
        playing = false;
      case CastMediaPlayerState.buffering:
        processingState = AudioProcessingState.buffering;
        playing = true;
      case CastMediaPlayerState.loading:
        processingState = AudioProcessingState.loading;
        playing = false;
      default:
        processingState = AudioProcessingState.idle;
        playing = false;
    }

    final castPosition =
        GoogleCastRemoteMediaClient.instance.playerPosition;

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
      processingState: processingState,
      playing: playing,
      updatePosition: castPosition,
      speed: status.playbackRate.toDouble(),
    ));

    // Update duration from Cast media info when queue item changes.
    final dur = status.mediaInformation?.duration;
    if (dur != null) {
      _effectiveDurationController.add(dur);
    }

    if (_book != null) _updateMediaItem();
  }

  Future<void> _saveCastPosition() async {
    if (_book == null || !_casting) return;
    final pos =
        GoogleCastRemoteMediaClient.instance.playerPosition;
    // For multi-file, we'd need to know the current queue item index.
    // For now, use currentIndex from player (set at cast start) for single-file,
    // or approximate from queue.
    final idx = _player.currentIndex ?? 0;
    await locator<PositionService>().savePosition(
      bookPath: _book!.path,
      chapterIndex: idx,
      position: pos,
      globalPositionMs: calculateGlobalPosition(
        chapterIndex: idx,
        chapterPosition: pos,
        chapterDurations: _book?.chapterDurations ?? [],
      ),
      totalDurationMs: _book!.duration?.inMilliseconds ?? 0,
    );
  }

  static String _castMimeType(String path) => CastServer.mimeType(path);

  // ── Completion handling ────────────────────────────────────────────────────

  Future<void> _onPlaybackCompleted() async {
    final book = _book;
    if (book == null) return;
    await locator<PositionService>().updateBookStatus(book.path, BookStatus.finished);

    if (book.source != AudiobookSource.drive) return;
    final folderId = book.driveMetadata?.folderId;
    if (folderId == null) return;

    final removeWhenFinished =
        await locator<PreferencesService>().getRemoveWhenFinished();
    if (!removeWhenFinished) return;

    // Queue removal after 1 minute — cancelled if the user presses play.
    _removalTimer?.cancel();
    _removalTimer = Timer(const Duration(minutes: 1), () async {
      // Only delete if the book is still finished (user hasn't restarted).
      final status =
          await locator<PositionService>().getBookStatus(book.path);
      if (status == BookStatus.finished) {
        await locator<DriveLibraryService>().deleteLocalFiles(folderId);
      }
      _removalTimer = null;
    });
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

    // If already casting, load the new book on the Cast device.
    if (_casting) {
      await _stopCasting();
      // Session is still connected, so restart casting with the new book.
      final connected =
          GoogleCastSessionManager.instance.connectionState ==
          GoogleCastConnectState.connected;
      if (connected) await _startCasting();
    }
  }

  // ── Position persistence ───────────────────────────────────────────────────

  Future<void> _savePosition() async {
    if (_book == null) return;
    final idx = _player.currentIndex ?? 0;
    final pos = _player.position;
    await locator<PositionService>().savePosition(
      bookPath: _book!.path,
      chapterIndex: idx,
      position: pos,
      globalPositionMs: calculateGlobalPosition(
        chapterIndex: idx,
        chapterPosition: pos,
        chapterDurations: _book?.chapterDurations ?? [],
      ),
      totalDurationMs: _book!.duration?.inMilliseconds ?? 0,
    );
  }

  @visibleForTesting
  static int calculateGlobalPosition({
    required int chapterIndex,
    required Duration chapterPosition,
    required List<Duration> chapterDurations,
  }) {
    int offset = 0;
    for (int i = 0; i < chapterIndex && i < chapterDurations.length; i++) {
      offset += chapterDurations[i].inMilliseconds;
    }
    return offset + chapterPosition.inMilliseconds;
  }

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
    _removalTimer?.cancel();
    _removalTimer = null;

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
        final currentPos = _casting
            ? GoogleCastRemoteMediaClient.instance.playerPosition
            : _player.position;
        var newPos = currentPos - rewindAmount;
        if (newPos < Duration.zero) newPos = Duration.zero;
        await seek(newPos);
      }
    }
    _lastPausedAt = null;

    if (_casting) {
      await GoogleCastRemoteMediaClient.instance.play();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    _lastPausedAt = DateTime.now();
    if (_casting) {
      await GoogleCastRemoteMediaClient.instance.pause();
      _saveCastPosition();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_casting) {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(
          position: position,
          relative: false,
          resumeState: GoogleCastMediaResumeState.unchanged,
        ),
      );
    } else {
      await _player.seek(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_casting) {
      final chapters = _book?.chapters;
      if (chapters != null && chapters.isNotEmpty) {
        // M4B: seek to next embedded chapter on Cast.
        final pos = GoogleCastRemoteMediaClient.instance.playerPosition;
        final idx = _book!.chapterIndexAt(pos);
        if (idx < chapters.length - 1) {
          await seek(chapters[idx + 1].start);
        }
      } else {
        await GoogleCastRemoteMediaClient.instance.queueNextItem();
      }
      return;
    }

    final chapters = _book?.chapters;
    if (chapters != null && chapters.isNotEmpty) {
      // M4B: seek to start of next embedded chapter
      final idx = _book!.chapterIndexAt(_player.position);
      if (idx < chapters.length - 1) {
        await _player.seek(chapters[idx + 1].start);
      }
      return;
    }
    // Multi-file: seek to next file
    final idx = _player.currentIndex ?? 0;
    final len = _player.sequence?.length ?? 1;
    if (idx < len - 1) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_casting) {
      final chapters = _book?.chapters;
      if (chapters != null && chapters.isNotEmpty) {
        // M4B: restart chapter or go to previous.
        final pos = GoogleCastRemoteMediaClient.instance.playerPosition;
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
        await GoogleCastRemoteMediaClient.instance.queuePrevItem();
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
    // Multi-file: restart file or go to previous
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
    if (_casting) {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(
          position: interval,
          relative: true,
          resumeState: GoogleCastMediaResumeState.unchanged,
        ),
      );
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
    if (_casting) {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(
          position: Duration(seconds: -secs),
          relative: true,
          resumeState: GoogleCastMediaResumeState.unchanged,
        ),
      );
      return;
    }
    final pos = _player.position - interval;
    await _player.seek(pos < Duration.zero ? Duration.zero : pos);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_casting) {
      await GoogleCastRemoteMediaClient.instance.setPlaybackRate(speed);
    }
    // Always set local speed too so it's remembered.
    await _player.setSpeed(speed);
  }

  @override
  Future<void> stop() async {
    if (_casting) {
      await _saveCastPosition();
      try {
        await GoogleCastRemoteMediaClient.instance.stop();
      } catch (_) {}
    }
    await _savePosition();
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
    if (_casting) return; // Cast status drives the broadcast when casting.

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
