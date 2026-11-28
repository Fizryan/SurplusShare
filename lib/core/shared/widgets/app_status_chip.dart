import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';

enum AppChipTone { primary, secondary, tertiary, error, neutral }

/// Compact Material 3 semantic pill badge strictly driven by [ColorScheme].
class AppStatusChip extends StatelessWidget {
  const new({
    required this.label,
    this.icon,
    this.tone = AppChipTone.neutral,
    super.key,
  });

  final String label;
  final IconData? icon;
  final AppChipTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (bg, fg) = switch (tone) {
      AppChipTone.primary => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      AppChipTone.secondary => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
      AppChipTone.tertiary => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
      ),
      AppChipTone.error => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      AppChipTone.neutral => (
        colorScheme.surfaceContainerHigh,
        colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
