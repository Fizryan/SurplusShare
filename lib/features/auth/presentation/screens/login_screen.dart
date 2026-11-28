import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_state.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_error_listener.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String _selectedDebugAccountId = kDebugMode
      ? DummyAuthAccounts.consumer.id
      : '';

  Future<void> _signInWithGoogle({String? debugAccountId}) async {
    if (ref.read(authNotifierProvider) is AuthLoading) return;
    await ref
        .read(authNotifierProvider.notifier)
        .signInWithGoogle(debugAccountId: debugAccountId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isLoading = ref.watch(
      authNotifierProvider.select((state) => state is AuthLoading),
    );
    final isDebugDemo = ref.watch(apiConfigProvider).isDemoMode;
    listenAuthError(ref);

    return AuthShell(
      title: 'Selamatkan Pangan Hari Ini',
      subtitle:
          'Masuk atau daftar otomatis dengan akun Google untuk menemukan '
          'makanan surplus berkualitas di sekitar Anda.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _ValuePill(
                icon: Icons.local_offer_outlined,
                label: 'Diskon hingga 70%',
              ),
              _ValuePill(
                icon: Icons.volunteer_activism_outlined,
                label: 'Donasi Terverifikasi',
              ),
              _ValuePill(icon: Icons.eco_outlined, label: 'Lacak Jejak CO2'),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Semantics(
            button: true,
            label: 'Lanjutkan dengan Google',
            child: FilledButton.tonal(
              key: const Key('google_sign_in_button'),
              onPressed: isLoading
                  ? null
                  : () => _signInWithGoogle(
                      debugAccountId: isDebugDemo
                          ? _selectedDebugAccountId
                          : null,
                    ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.circular(AppRadius.md),
                ),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GoogleGlyph(
                          backgroundColor: colorScheme.onPrimary,
                          foregroundColor: colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            'Lanjutkan dengan Google',
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelLarge?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Satu klik untuk masuk atau membuat akun baru secara aman '
            'tanpa perlu mengingat password.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (isDebugDemo) ...[
            const SizedBox(height: AppSpacing.xl),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: colorScheme.tertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Mode Demo Lokal — Pilih Role Akun Google',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final account in DummyAuthAccounts.all)
                  ChoiceChip(
                    key: Key('debug_role_${account.role.name}'),
                    label: Text(AppFormatters.roleLabel(account.role)),
                    selected: _selectedDebugAccountId == account.id,
                    onSelected: isLoading
                        ? null
                        : (_) => setState(
                            () => _selectedDebugAccountId = account.id,
                          ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const new({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const new({required this.backgroundColor, required this.foregroundColor});

  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        'G',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
