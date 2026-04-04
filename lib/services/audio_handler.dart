import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/audiobook.dart';
import 'position_service.dart';

class AudioVaultHandler extends BaseAudioHandler {
  final _player = AudioPlayer();
  Audiobook? _book;
  Uri? _artUri;
  Timer? _saveTimer;

  AudioPlayer get player => _player;
  Audiobook? get currentBook => _book;

  AudioVaultHandler() {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (error, stackTrace) {
        debugPrint('[AudioVault:Player] Playback error: $error');
      },
    );
    _player.currentIndexStream.listen(
      (_) => _broadcastState(null),
      onError: (error, stackTrace) {
        debugPrint('[AudioVault:Player] Index stream error: $error');
      },
    );

    // Start/stop periodic save as playback state changes.
    _player.playingStream.listen((playing) {
      if (playing) {
        _saveTimer ??= Timer.periodic(
            const Duration(seconds: 5), (_) => _savePosition());
      } else {
        _saveTimer?.cancel();
        _saveTimer = null;
        _savePosition(); // immediate save on pause
      }
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
    final saved = await PositionService().getPosition(book.path);

    final sources =
        book.audioFiles.map((p) => AudioSource.uri(Uri.file(p))).toList();
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: saved?.chapterIndex ?? 0,
      initialPosition: saved?.position ?? Duration.zero,
    );
    _updateMediaItem();
  }

  // ── Position persistence ───────────────────────────────────────────────────

  Future<void> _savePosition() async {
    if (_book == null) return;
    final idx = _player.currentIndex ?? 0;
    final pos = _player.position;
    await PositionService().savePosition(
      bookPath: _book!.path,
      chapterIndex: idx,
      position: pos,
      globalPositionMs: _globalPositionMs(idx, pos),
      totalDurationMs: _book!.duration?.inMilliseconds ?? 0,
    );
  }

  int _globalPositionMs(int chapterIndex, Duration chapterPosition) {
    int offset = 0;
    final durations = _book?.chapterDurations ?? [];
    for (int i = 0; i < chapterIndex && i < durations.length; i++) {
      offset += durations[i].inMilliseconds;
    }
    return offset + chapterPosition.inMilliseconds;
  }

  // ── Playback controls ──────────────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final idx = _player.currentIndex ?? 0;
    final len = _player.sequence?.length ?? 1;
    if (idx < len - 1) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
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
    final dur = _player.duration ?? Duration.zero;
    final pos = _player.position + const Duration(seconds: 30);
    await _player.seek(pos > dur ? dur : pos);
  }

  @override
  Future<void> rewind() async {
    final pos = _player.position - const Duration(seconds: 30);
    await _player.seek(pos < Duration.zero ? Duration.zero : pos);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  // ── State broadcasting ─────────────────────────────────────────────────────

  void _broadcastState(PlaybackEvent? event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.fastForward,
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
        'chapterCount': _book!.audioFiles.length,
      },
    ));
  }
}
