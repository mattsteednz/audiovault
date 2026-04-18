import 'package:flutter/material.dart';

import '../locator.dart';
import '../services/sleep_timer_controller.dart';

/// Small moon icon + mm:ss countdown for the active sleep timer.
///
/// Renders [SizedBox.shrink] when no timer is active so the surface layout
/// (e.g. the library AppBar) doesn't jump when the user toggles one on.
class SleepTimerIndicator extends StatelessWidget {
  /// Called when the user taps the indicator — typically to open the timer
  /// controls. If null, tapping does nothing.
  final VoidCallback? onTap;

  const SleepTimerIndicator({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final controller = locator<SleepTimerController>();
    return ValueListenableBuilder<Duration?>(
      valueListenable: controller.remaining,
      builder: (_, remaining, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: controller.stopAtChapterEnd,
          builder: (_, eoc, __) {
            if (remaining == null && !eoc) return const SizedBox.shrink();
            final label = remaining != null
                ? _fmt(remaining)
                : 'EOC'; // end-of-chapter
            return _Chip(label: label, onTap: onTap);
          },
        );
      },
    );
  }

  static String _fmt(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '${h}h${m}m';
    }
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _Chip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bedtime_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'Sleep timer: $label remaining',
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ),
    );
  }
}
