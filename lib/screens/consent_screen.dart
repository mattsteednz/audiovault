import 'package:flutter/material.dart';

/// Shown once on first launch to get the user's telemetry consent.
class ConsentScreen extends StatelessWidget {
  final void Function(bool accepted) onChoice;

  const ConsentScreen({super.key, required this.onChoice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.privacy_tip_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 28),
              Text(
                'Help us improve AudioVault',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'We use Google Firebase to collect crash reports and track that '
                'you\'re using the app. No personal data like book titles or '
                'files are ever sent. You can opt out anytime.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () => onChoice(true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Accept'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => onChoice(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Decline'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
