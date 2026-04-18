import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:just_audio/just_audio.dart';
import '../models/audiobook.dart';
import 'cast_server.dart';
import 'position_persister.dart';
import 'telemetry_service.dart';

/// Owns all Google Cast state for AudioVaultHandler:
///
/// * the local HTTP server that streams media bytes to the receiver
/// * the Cast session / status / position subscriptions
/// * the casting flag + change stream consumed by the UI
///
/// The audio handler routes playback commands here whenever [isCasting] is
/// true. Everything Cast-SDK-specific lives in this file so the handler
/// itself stays source-agnostic.
class CastController {
  CastController({
    required this.localPlayer,
    required this.persister,
    required this.getBook,
    required this.onEffectivePosition,
    required this.onEffectiveDuration,
    required this.onStatusChanged,
  });

  final AudioPlayer localPlayer;
  final PositionPersister persister;
  final Audiobook? Function() getBook;
  final void Function(Duration position) onEffectivePosition;
  final void Function(Duration? duration) onEffectiveDuration;
  final void Function(GoggleCastMediaStatus status) onStatusChanged;

  final CastServer _server = CastServer();
  String? _baseUrl;
  bool _casting = false;

  bool get isCasting => _casting;

  final _castingController = StreamController<bool>.broadcast();
  Stream<bool> get castingStream => _castingController.stream;

  StreamSubscription? _sessionSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _positionSub;

  /// Start listening to Cast session changes. Call once at handler init.
  void listenForSessions() {
    _sessionSub = GoogleCastSessionManager.instance.currentSessionStream
        .listen((_) {
      final connected =
          GoogleCastSessionManager.instance.connectionState ==
              GoogleCastConnectState.connected;
      if (connected && !_casting) {
        start();
      } else if (!connected && _casting) {
        stop();
      }
    });
  }

  /// Hand playback off from the local player to the connected Cast receiver.
  Future<void> start() async {
    final book = getBook();
    if (book == null) return;

    _casting = true;
    _castingController.add(true);

    final wasPlaying = localPlayer.playing;
    final position = localPlayer.position;
    final currentIndex = localPlayer.currentIndex ?? 0;
    final speed = localPlayer.speed;

    await localPlayer.pause();

    try {
      _baseUrl = await _server.start(
        book.audioFiles,
        coverPath: book.coverImagePath,
      );
    } catch (e) {
      debugPrint('[AudioVault:Cast] Failed to start server: $e');
      _casting = false;
      _castingController.add(false);
      if (wasPlaying) localPlayer.play();
      return;
    }

    Uri? coverUrl;
    if (book.coverImagePath != null) {
      coverUrl = Uri.parse('$_baseUrl/cover');
    }

    final client = GoogleCastRemoteMediaClient.instance;

    _statusSub = client.mediaStatusStream.listen((status) {
      if (status != null) onStatusChanged(status);
    });
    _positionSub =
        client.playerPositionStream.listen(onEffectivePosition);

    persister.stopPeriodic();
    persister.startPeriodic();

    try {
      if (book.audioFiles.length == 1) {
        await client.loadMedia(
          GoogleCastMediaInformation(
            contentId: book.path,
            streamType: CastMediaStreamType.buffered,
            contentUrl: Uri.parse('$_baseUrl/audio/0'),
            contentType: CastServer.mimeType(book.audioFiles[0]),
            metadata: GoogleCastMusicMediaMetadata(
              title: book.title,
              artist: book.author,
              images: coverUrl != null
                  ? [GoogleCastImage(url: coverUrl)]
                  : null,
            ),
            duration: book.duration,
          ),
          autoPlay: wasPlaying,
          playPosition: position,
          playbackRate: speed,
        );
        onEffectiveDuration(book.duration);
      } else {
        final items = book.audioFiles.asMap().entries.map((e) {
          return GoogleCastQueueItem(
            mediaInformation: GoogleCastMediaInformation(
              contentId: '${book.path}/${e.key}',
              streamType: CastMediaStreamType.buffered,
              contentUrl: Uri.parse('$_baseUrl/audio/${e.key}'),
              contentType: CastServer.mimeType(e.value),
              metadata: GoogleCastMusicMediaMetadata(
                title: book.title,
                artist: book.author,
                images: coverUrl != null
                    ? [GoogleCastImage(url: coverUrl)]
                    : null,
              ),
              duration: e.key < book.chapterDurations.length
                  ? book.chapterDurations[e.key]
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
        if (currentIndex < book.chapterDurations.length) {
          onEffectiveDuration(book.chapterDurations[currentIndex]);
        }
      }
      TelemetryService.logEvent('cast_start', parameters: {
        'file_count': book.audioFiles.length,
      });
    } catch (e) {
      debugPrint('[AudioVault:Cast] Failed to load media on Cast: $e');
      _casting = false;
      _castingController.add(false);
      await _statusSub?.cancel();
      await _positionSub?.cancel();
      _statusSub = null;
      _positionSub = null;
      persister.stopPeriodic();
      await _server.stop();
      if (wasPlaying) localPlayer.play();
    }
  }

  /// Tear down Cast session and resume local playback at the last known
  /// Cast position.
  Future<void> stop() async {
    if (!_casting) return;

    Duration castPosition = Duration.zero;
    try {
      castPosition = GoogleCastRemoteMediaClient.instance.playerPosition;
    } catch (_) {}

    await _statusSub?.cancel();
    await _positionSub?.cancel();
    _statusSub = null;
    _positionSub = null;
    persister.stopPeriodic();

    await _server.stop();
    TelemetryService.logEvent('cast_stop');

    _casting = false;
    _castingController.add(false);

    final book = getBook();
    if (book != null) {
      await localPlayer.seek(castPosition);
      onEffectivePosition(localPlayer.position);
      onEffectiveDuration(localPlayer.duration);
    }
  }

  /// True if a Cast session is currently connected (regardless of our
  /// [_casting] state — used after [stop] to decide whether a fresh book
  /// should be re-cast).
  bool get isSessionConnected =>
      GoogleCastSessionManager.instance.connectionState ==
      GoogleCastConnectState.connected;

  // ── Playback command delegates (no-op when not casting) ─────────────────

  Duration get position =>
      GoogleCastRemoteMediaClient.instance.playerPosition;

  Future<void> play() => GoogleCastRemoteMediaClient.instance.play();
  Future<void> pause() => GoogleCastRemoteMediaClient.instance.pause();

  Future<void> seekAbsolute(Duration p) =>
      GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(
          position: p,
          relative: false,
          resumeState: GoogleCastMediaResumeState.unchanged,
        ),
      );

  Future<void> seekRelative(Duration delta) =>
      GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(
          position: delta,
          relative: true,
          resumeState: GoogleCastMediaResumeState.unchanged,
        ),
      );

  Future<void> setSpeed(double speed) =>
      GoogleCastRemoteMediaClient.instance.setPlaybackRate(speed);

  Future<void> queueNext() =>
      GoogleCastRemoteMediaClient.instance.queueNextItem();

  Future<void> queuePrev() =>
      GoogleCastRemoteMediaClient.instance.queuePrevItem();

  /// Stop the receiver. Swallows errors — the session may already be dead.
  Future<void> stopClient() async {
    try {
      await GoogleCastRemoteMediaClient.instance.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _sessionSub?.cancel();
    await _statusSub?.cancel();
    await _positionSub?.cancel();
    await _server.stop();
    await _castingController.close();
  }
}

// ── Pure helpers (testable) ───────────────────────────────────────────────────

/// Maps a Cast receiver's playback state to the `audio_service` equivalent
/// used by the platform notification. Pure.
({AudioProcessingState processingState, bool playing}) mapCastPlayerState(
  CastMediaPlayerState state,
) {
  switch (state) {
    case CastMediaPlayerState.playing:
      return (
        processingState: AudioProcessingState.ready,
        playing: true,
      );
    case CastMediaPlayerState.paused:
      return (
        processingState: AudioProcessingState.ready,
        playing: false,
      );
    case CastMediaPlayerState.buffering:
      return (
        processingState: AudioProcessingState.buffering,
        playing: true,
      );
    case CastMediaPlayerState.loading:
      return (
        processingState: AudioProcessingState.loading,
        playing: false,
      );
    default:
      return (
        processingState: AudioProcessingState.idle,
        playing: false,
      );
  }
}
