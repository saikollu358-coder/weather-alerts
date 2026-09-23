import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/validation/validators.dart';
import '../../../domain/entities/auth_user.dart';
import '../../../routing/app_routes.dart';
import '../../authentication/application/auth_providers.dart';

/// Profile: identity + account type + editable display name + settings link.
///
/// Editing is only offered for cloud accounts; the local/guest session has no
/// editable profile. Entry point is the app-bar person button on the dashboard
/// shell.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = auth.user;
    final isCloud = user != null && !user.isLocalGuest;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    child: Text(
                      (user?.displayName.isNotEmpty ?? false)
                          ? user!.displayName.substring(0, 1).toUpperCase()
                          : '?',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          user?.displayName ?? 'No profile',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      if (isCloud)
                        IconButton(
                          key: const ValueKey('edit_profile_button'),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit name',
                          onPressed: () =>
                              _showEditNameDialog(context, ref, user),
                        ),
                    ],
                  ),
                  if (user?.email != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        user!.email!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isCloud
                          ? scheme.secondaryContainer
                          : scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isCloud
                          ? 'Cloud account'
                          : 'Local mode — no cloud account',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isCloud
                            ? scheme.onSecondaryContainer
                            : scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              key: const ValueKey('open_settings_row'),
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Notifications & settings'),
              subtitle: const Text(
                'Alert preferences, permissions and app settings',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(RoutePath.settings),
            ),
          ),
          const SizedBox(height: 24),
          if (!isCloud)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'This build has no Firebase configuration, so you are in '
                  'local-only mode. Your weather data stays on this device, '
                  'and profile editing requires a cloud account.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            FilledButton.icon(
              key: const ValueKey('logout_button'),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          const SizedBox(height: 16),
          Text(
            AppConstants.assessmentDisclaimer,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, WidgetRef ref, AuthUser user) {
    showDialog<void>(
      context: context,
      builder: (_) => _EditNameDialog(ref: ref, user: user),
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.ref, required this.user});

  final WidgetRef ref;
  final AuthUser user;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.user.name ?? '');
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final message = await widget.ref
        .read(authControllerProvider.notifier)
        .updateProfile(name: _controller.text);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(message ?? 'Profile updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('profile_name_field'),
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: Validators.name,
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel_profile_button'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save_profile_button'),
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}