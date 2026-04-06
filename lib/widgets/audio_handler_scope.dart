import 'package:flutter/material.dart';
import '../services/audio_handler.dart';

/// Provides [AudioVaultHandler] and the app-wide [ThemeMode] notifier to the
/// widget tree via an [InheritedWidget].
class AudioHandlerScope extends InheritedWidget {
  final AudioVaultHandler audioHandler;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  const AudioHandlerScope({
    super.key,
    required this.audioHandler,
    required this.themeModeNotifier,
    required super.child,
  });

  static AudioHandlerScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AudioHandlerScope>();
    assert(scope != null, 'No AudioHandlerScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AudioHandlerScope oldWidget) =>
      audioHandler != oldWidget.audioHandler ||
      themeModeNotifier != oldWidget.themeModeNotifier;
}
