import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/shared/widgets/app_surface_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';

/// Calm Material 3 loading placeholder card built strictly from [ColorScheme].
class AppSkeletonCard extends StatelessWidget {
  const new({this.lines = 3, super.key});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final shimmerColor = Theme.of(context).colorScheme.surfaceContainerHighest
        .withValues(alpha: 0.7);

    return Semantics(
      label: 'Memuat data',
      child: AppSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SkeletonBar(width: 84, height: 22, color: shimmerColor),
                const SizedBox(width: AppSpacing.sm),
                _SkeletonBar(width: 68, height: 22, color: shimmerColor),
                const Spacer(),
                _SkeletonBar(width: 64, height: 22, color: shimmerColor),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _SkeletonBar(width: 180, height: 18, color: shimmerColor),
            for (var i = 0; i < lines - 1; i++) ...[
              const SizedBox(height: AppSpacing.sm),
              _SkeletonBar(
                width: i.isEven ? double.infinity : 140,
                height: 12,
                color: shimmerColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const new({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.circular(AppRadius.sm),
      ),
    );
  }
}
