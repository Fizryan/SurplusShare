import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/shared/widgets/app_status_chip.dart';
import 'package:surplus_share/core/shared/widgets/app_surface_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/distribution/presentation/widgets/distribution_route_map_sheet.dart';

class DistributionTaskCard extends StatelessWidget {
  const new({
    required this.task,
    required this.isBusy,
    this.showPickupPin = false,
    this.showDeliveryPin = false,
    this.onPinCopied,
    this.onAccept,
    this.onMarkPickedUp,
    this.onMarkDelivered,
    this.onCancel,
    super.key,
  });

  final DistributionTask task;
  final bool isBusy;
  final bool showPickupPin;
  final bool showDeliveryPin;
  final VoidCallback? onPinCopied;
  final VoidCallback? onAccept;
  final VoidCallback? onMarkPickedUp;
  final VoidCallback? onMarkDelivered;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final distanceKm = task.storeLocation.distanceInKmTo(
      task.recipientLocation,
    );

    final (statusLabel, statusTone) = switch (task.status) {
      DistributionStatus.open => ('Menunggu Relawan', AppChipTone.secondary),
      DistributionStatus.accepted => ('Diambil Relawan', AppChipTone.primary),
      DistributionStatus.pickedUp => ('Sedang Diantar', AppChipTone.tertiary),
      DistributionStatus.delivered => ('Terkirim', AppChipTone.primary),
      DistributionStatus.cancelled => ('Dibatalkan', AppChipTone.error),
    };

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppStatusChip(
                label: statusLabel,
                icon: Icons.local_shipping_outlined,
                tone: statusTone,
              ),
              AppStatusChip(
                label:
                    '${task.portions} porsi • '
                    '${distanceKm.toStringAsFixed(1)} km',
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            task.listingTitle,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RouteLine(
            icon: Icons.storefront_outlined,
            color: colorScheme.primary,
            prefix: 'Pickup',
            place: task.partnerName,
            address: task.storeAddress,
          ),
          const SizedBox(height: AppSpacing.xs),
          _RouteLine(
            icon: Icons.volunteer_activism_outlined,
            color: colorScheme.tertiary,
            prefix: 'Drop-off',
            place: task.recipientName,
            address: task.recipientAddress,
          ),
          if (task.volunteerName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Relawan: ${task.volunteerName}',
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (showPickupPin &&
              task.status == DistributionStatus.accepted &&
              task.pickupPin != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PinBanner(
              label: 'PIN Pickup untuk Relawan (Berikan saat ambil di toko)',
              pin: task.pickupPin!,
              onPinCopied: onPinCopied,
            ),
          ],
          if (showDeliveryPin &&
              task.status == DistributionStatus.pickedUp &&
              task.deliveryPin != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PinBanner(
              label: 'PIN Terima Paket (Berikan saat relawan tiba)',
              pin: task.deliveryPin!,
              onPinCopied: onPinCopied,
            ),
          ],
          if (onMarkPickedUp != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Minta 6 digit PIN Pickup dari kasir ${task.partnerName} saat '
              'mengambil paket.',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
            ),
          ] else if (onMarkDelivered != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Minta 6 digit PIN Terima dari pengurus ${task.recipientName} '
              'saat paket diserahkan.',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.tertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => showAppBottomSheet<void>(
                  context: context,
                  builder: (_) => DistributionRouteMapSheet(task: task),
                ),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Lihat Peta'),
              ),
              if (onCancel != null)
                OutlinedButton(
                  onPressed: isBusy ? null : onCancel,
                  child: const Text('Batalkan'),
                ),
              if (onAccept != null)
                FilledButton(
                  onPressed: isBusy ? null : onAccept,
                  child: const Text('Ambil Tugas'),
                ),
              if (onMarkPickedUp != null)
                FilledButton.icon(
                  onPressed: isBusy ? null : onMarkPickedUp,
                  icon: const Icon(Icons.pin_outlined, size: 16),
                  label: const Text('Konfirmasi Pickup'),
                ),
              if (onMarkDelivered != null)
                FilledButton.icon(
                  onPressed: isBusy ? null : onMarkDelivered,
                  icon: const Icon(Icons.pin_outlined, size: 16),
                  label: const Text('Selesai Diantar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinBanner extends StatelessWidget {
  const new({required this.label, required this.pin, this.onPinCopied});

  final String label;
  final String pin;
  final VoidCallback? onPinCopied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: AppRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pin,
                  style: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Salin PIN',
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: pin)));
              onPinCopied?.call();
            },
            icon: Icon(
              Icons.copy_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const new({
    required this.icon,
    required this.color,
    required this.prefix,
    required this.place,
    required this.address,
  });

  final IconData icon;
  final Color color;
  final String prefix;
  final String place;
  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            '$prefix: $place — $address',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
