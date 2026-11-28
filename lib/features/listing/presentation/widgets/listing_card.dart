import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/shared/widgets/app_status_chip.dart';
import 'package:surplus_share/core/shared/widgets/app_surface_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';

class ListingCard extends StatelessWidget {
  const new({
    required this.listing,
    this.onAction,
    this.distanceLabel,
    this.isFavoritePartner = false,
    this.onToggleFavorite,
    this.canConvertToDonation = false,
    this.onConvertToDonation,
    this.onAllocateVolunteer,
    super.key,
  });

  final SurplusListing listing;
  final VoidCallback? onAction;
  final String? distanceLabel;
  final bool isFavoritePartner;
  final VoidCallback? onToggleFavorite;
  final bool canConvertToDonation;
  final VoidCallback? onConvertToDonation;
  final VoidCallback? onAllocateVolunteer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDonation = listing.channel == ListingChannel.donation;
    final safety = listing.foodSafety;

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppStatusChip(
                label: isDonation ? 'Donasi Gratis' : 'Diskon Surplus',
                icon: isDonation
                    ? Icons.volunteer_activism_outlined
                    : Icons.local_offer_outlined,
                tone: isDonation ? AppChipTone.tertiary : AppChipTone.primary,
              ),
              if (distanceLabel != null)
                AppStatusChip(
                  label: distanceLabel!,
                  icon: Icons.near_me_outlined,
                ),
              if (listing.volunteerAllocatedPortions > 0)
                AppStatusChip(
                  label: '${listing.volunteerAllocatedPortions} porsi relawan',
                  icon: Icons.local_shipping_outlined,
                  tone: AppChipTone.secondary,
                ),
              _ListingCountdownChip(listingId: listing.id),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listing.partnerName,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (listing.address != null &&
                        listing.address!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              listing.address!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onToggleFavorite != null)
                IconButton(
                  tooltip: isFavoritePartner
                      ? 'Hapus mitra favorit'
                      : 'Tandai mitra favorit',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavoritePartner
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavoritePartner
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (safety != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                AppStatusChip(
                  label: AppFormatters.halalLabel(safety.halalStatus),
                  icon: safety.halalStatus == HalalStatus.nonHalal
                      ? Icons.info_outline_rounded
                      : Icons.verified_outlined,
                  tone: safety.halalStatus == HalalStatus.nonHalal
                      ? AppChipTone.neutral
                      : AppChipTone.secondary,
                ),
                AppStatusChip(
                  label: AppFormatters.foodCategoryLabel(safety.category),
                ),
                if (safety.allergens.isNotEmpty)
                  AppStatusChip(
                    label: _allergensSummary(safety.allergens),
                    icon: Icons.warning_amber_rounded,
                    tone: AppChipTone.error,
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isDonation
                        ? 'GRATIS'
                        : AppFormatters.formatRupiah(listing.discountedPrice),
                    style: textTheme.titleMedium?.copyWith(
                      color: isDonation
                          ? colorScheme.tertiary
                          : colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _stockAndOriginalPriceLabel(
                      remaining: listing.remainingQuantity,
                      originalPrice: listing.originalPrice,
                      isDonation: isDonation,
                    ),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              _ListingActionButtons(
                isDonation: isDonation,
                canConvertToDonation: canConvertToDonation,
                onConvertToDonation: onConvertToDonation,
                onAllocateVolunteer: onAllocateVolunteer,
                onAction: onAction,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _allergensSummary(Set<FoodAllergen> allergens) {
  final names = allergens.map(AppFormatters.allergenLabel).join(', ');
  return 'Alergen: $names';
}

String _stockAndOriginalPriceLabel({
  required int remaining,
  required int originalPrice,
  required bool isDonation,
}) {
  if (originalPrice > 0 && !isDonation) {
    final normal = AppFormatters.formatRupiah(originalPrice);
    return 'Sisa $remaining porsi • Normal $normal';
  }
  return 'Sisa $remaining porsi';
}

/// Isolated 1-second countdown leaf widget so [ListingCard] and parent screens
/// never rebuild on every tick.
class _ListingCountdownChip extends ConsumerWidget {
  const new({required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdown = ref.watch(listingCountdownProvider(listingId));
    if (countdown == null) return const SizedBox.shrink();

    final tone = switch (countdown.urgency) {
      PickupUrgency.critical || PickupUrgency.expired => AppChipTone.error,
      PickupUrgency.closingSoon => AppChipTone.tertiary,
      PickupUrgency.normal => AppChipTone.secondary,
    };

    return Semantics(
      label: 'Sisa waktu ambil ${countdown.formattedCountdown}',
      child: AppStatusChip(
        label: countdown.isExpired ? 'Berakhir' : countdown.formattedCountdown,
        icon: Icons.timer_outlined,
        tone: tone,
      ),
    );
  }
}

/// Isolated action button row that disables during in-flight reservations.
class _ListingActionButtons extends ConsumerWidget {
  const new({
    required this.isDonation,
    required this.canConvertToDonation,
    required this.onConvertToDonation,
    required this.onAllocateVolunteer,
    required this.onAction,
  });

  final bool isDonation;
  final bool canConvertToDonation;
  final VoidCallback? onConvertToDonation;
  final VoidCallback? onAllocateVolunteer;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = ref.watch(
      reservationNotifierProvider.select((state) => state.isLoading),
    );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        if (onAllocateVolunteer != null)
          OutlinedButton(
            onPressed: isBusy ? null : onAllocateVolunteer,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Alokasi Relawan'),
          ),
        if (canConvertToDonation && onConvertToDonation != null)
          OutlinedButton(
            onPressed: isBusy ? null : onConvertToDonation,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Ke Donasi'),
          ),
        if (onAction != null)
          FilledButton(
            onPressed: isBusy ? null : onAction,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(isDonation ? 'Klaim' : 'Pesan'),
          ),
      ],
    );
  }
}
