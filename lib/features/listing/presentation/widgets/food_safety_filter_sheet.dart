import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';

class FoodSafetyFilterSheet extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final filter = ref.watch(foodSafetyFilterProvider);
    final notifier = ref.read(foodSafetyFilterProvider.notifier);

    return AppBottomSheetScaffold(
      title: 'Filter Keamanan & Halal',
      trailing: TextButton(
        onPressed: filter.isActive ? notifier.reset : null,
        child: const Text('Reset'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hanya Makanan Halal'),
            subtitle: const Text('Sembunyikan menu Non-Halal'),
            value: filter.halalOnly,
            onChanged: (v) => notifier.setHalalOnly(enabled: v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wajib Halal Bersertifikat'),
            subtitle: const Text('Hanya tampilkan sertifikat Halal MUI'),
            value: filter.halalCertifiedOnly,
            onChanged: (v) => notifier.setHalalCertifiedOnly(enabled: v),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Hindari Alergen',
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final allergen in FoodAllergen.values)
                FilterChip(
                  label: Text(AppFormatters.allergenLabel(allergen)),
                  selected: filter.excludedAllergens.contains(allergen),
                  onSelected: (_) => notifier.toggleExcludedAllergen(allergen),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Kategori Makanan',
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final cat in FoodCategory.values)
                FilterChip(
                  label: Text(AppFormatters.foodCategoryLabel(cat)),
                  selected: filter.categories.contains(cat),
                  onSelected: (_) => notifier.toggleCategory(cat),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Terapkan Filter'),
          ),
        ],
      ),
    );
  }
}
