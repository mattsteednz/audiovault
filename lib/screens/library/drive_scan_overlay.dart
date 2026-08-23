import 'package:flutter/material.dart';

/// Animated overlay shown while the library is being scanned.
///
/// Features:
/// - Pulsing headphones icon (scale + opacity loop)
/// - Status text that cross-fades between phases
/// - A rotating audiobook tip that changes every few seconds
class DriveScanOverlay extends StatefulWidget {
  final String status;

  const DriveScanOverlay({super.key, required this.status});

  @override
  State<DriveScanOverlay> createState() => _DriveScanOverlayState();
}

class _DriveScanOverlayState extends State<DriveScanOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  late final AnimationController _tipController;
  int _tipIndex = 0;

  static const _tips = [
    'Tip: Tap the chapter label in the player to jump to any chapter.',
    'Tip: Set the sleep timer to stop at the end of a chapter.',
    'Tip: Add bookmarks while listening to save your favourite moments.',
    'Tip: Your listening position syncs across devices via Drive.',
    'Tip: Use the sort menu to find your next listen by author.',
    'Tip: Download a book to listen without an internet connection.',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseOpacity = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _tipController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _tipIndex = (_tipIndex + 1) % _tips.length;
          });
          _tipController.forward(from: 0);
        }
      });
    _tipController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing icon
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Opacity(
                opacity: _pulseOpacity.value,
                child: Transform.scale(
                  scale: _pulseScale.value,
                  child: Icon(
                    Icons.headphones_rounded,
                    size: 64,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Cross-fading status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Text(
                widget.status,
                key: ValueKey(widget.status),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),

            // Rotating tip
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Text(
                _tips[_tipIndex],
                key: ValueKey(_tipIndex),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
