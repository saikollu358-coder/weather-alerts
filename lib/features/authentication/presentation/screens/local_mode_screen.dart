import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_providers.dart';
import '../widgets/auth_scaffold.dart';

/// Entry gate shown when the app cannot reach any cloud backend.
///
/// A build without a connected Firebase project cannot sign in or register, so
/// instead of silently skipping the login page this screen explains why the
/// login screen isn't shown and lets the user explicitly opt into the
/// offline-first "local guest" experience.
class LocalModeScreen extends ConsumerWidget {
  const LocalModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AuthScaffold(
      children: [
        Text('Running in local mode', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'This build is not connected to your cloud account, so sign-in and '
          'registration are not available right now.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bullet(icon: Icons.wifi_off_outlined, scheme: scheme, text: 'No cloud account or database connection.'),
              const SizedBox(height: 8),
              _Bullet(icon: Icons.person_off_outlined, scheme: scheme, text: 'Profile editing, login and cross-device sync are disabled.'),
              const SizedBox(height: 8),
              _Bullet(icon: Icons.phone_android, scheme: scheme, text: 'Weather alerts and your saved locations still work fully on this device.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('continue_locally_button'),
          onPressed: () => ref.read(localAuthServiceProvider).startLocalGuest(),
          icon: const Icon(Icons.cloud_off_outlined),
          label: const Text('Continue as local guest'),
        ),
        const SizedBox(height: 8),
        Text(
          'To enable sign-in, add the Firebase config for your platform '
          '(see documentation/FIREBASE_SETUP.md) and rebuild.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        const AuthDisclaimer(),
      ],
    );
  }
}

/// Single line of the local-mode consequences list.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.scheme, required this.text});

  final IconData icon;
  final ColorScheme scheme;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}