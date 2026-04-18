import 'package:audio_service/audio_service.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/services/cast_controller.dart';

void main() {
  group('mapCastPlayerState', () {
    test('playing → ready + playing', () {
      final r = mapCastPlayerState(CastMediaPlayerState.playing);
      expect(r.processingState, AudioProcessingState.ready);
      expect(r.playing, isTrue);
    });

    test('paused → ready + not playing', () {
      final r = mapCastPlayerState(CastMediaPlayerState.paused);
      expect(r.processingState, AudioProcessingState.ready);
      expect(r.playing, isFalse);
    });

    test('buffering → buffering + playing (buffering keeps the spinner)', () {
      final r = mapCastPlayerState(CastMediaPlayerState.buffering);
      expect(r.processingState, AudioProcessingState.buffering);
      expect(r.playing, isTrue);
    });

    test('loading → loading + not playing', () {
      final r = mapCastPlayerState(CastMediaPlayerState.loading);
      expect(r.processingState, AudioProcessingState.loading);
      expect(r.playing, isFalse);
    });

    test('idle / unknown → idle + not playing', () {
      final r = mapCastPlayerState(CastMediaPlayerState.idle);
      expect(r.processingState, AudioProcessingState.idle);
      expect(r.playing, isFalse);
    });
  });
}
