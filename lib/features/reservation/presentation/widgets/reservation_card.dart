import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/shared/widgets/app_status_chip.dart';
import 'package:surplus_share/core/shared/widgets/app_surface_card.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';

class ReservationCard extends StatelessWidget {
  const new({
    required this.reservation,
    this.now,
    this.isBusy = false,
    this.showPickupPin = true,
    this.onConfirmPayment,
    this.onCancel,
    this.onValidatePin,
    this.onPinCopied,
    super.key,
  });

  final Reservation reservation;
  final DateTime? now;
  final bool isBusy;
  final bool showPickupPin;
  final VoidCallback? onConfirmPayment;
  final VoidCallback? onCancel;
  final VoidCallback? onValidatePin;
  final VoidCallback? onPinCopied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final status = reservation.effectiveStatus(now: now);

    final (statusLabel, statusTone) = switch (status) {
      ReservationStatus.pendingPayment => (
        'Menunggu Pembayaran',
        AppChipTone.secondary,
      ),
      ReservationStatus.confirmed => ('Siap Diambil', AppChipTone.primary),
      ReservationStatus.completed => ('Selesai', AppChipTone.tertiary),
      ReservationStatus.cancelled => ('Dibatalkan', AppChipTone.neutral),
      ReservationStatus.expired => ('Kedaluwarsa', AppChipTone.error),
    };

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppStatusChip(label: statusLabel, tone: statusTone),
              AppStatusChip(
                label: reservation.channel == ListingChannel.donation
                    ? 'Donasi • ${reservation.quantity} porsi'
                    : '${AppFormatters.formatRupiah(reservation.totalAmount)} '
                          '• ${reservation.quantity} porsi',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reservation.listingTitle,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Jendela ambil: ${reservation.pickupWindow.formatWindowRange()}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (status == ReservationStatus.pendingPayment &&
              reservation.paymentSession != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.circular(AppRadius.md),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Link Pembayaran '
                    '(${reservation.paymentSession!.method.name.toUpperCase()}'
                    ')',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    reservation.paymentSession!.checkoutUrl.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showPickupPin &&
              status == ReservationStatus.confirmed &&
              reservation.pickupPin != null) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: 'Kode PIN serah terima ${reservation.pickupPin}',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
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
                            'Kode PIN Serah Terima',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            reservation.pickupPin!,
                            style: textTheme.headlineSmall?.copyWith(
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
                        unawaited(
                          Clipboard.setData(
                            ClipboardData(text: reservation.pickupPin!),
                          ),
                        );
                        onPinCopied?.call();
                      },
                      icon: Icon(
                        Icons.copy_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (status == ReservationStatus.completed &&
              reservation.receipt != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppStatusChip(
              label: 'Bukti: ${reservation.receipt!.receiptId}',
              icon: Icons.verified_rounded,
              tone: AppChipTone.tertiary,
            ),
          ],
          if (onConfirmPayment != null ||
              onCancel != null ||
              onValidatePin != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.end,
              children: [
                if (onCancel != null)
                  OutlinedButton(
                    onPressed: isBusy ? null : onCancel,
                    child: const Text('Batalkan'),
                  ),
                if (onConfirmPayment != null)
                  FilledButton(
                    onPressed: isBusy ? null : onConfirmPayment,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    child: const Text('Konfirmasi Bayar'),
                  ),
                if (onValidatePin != null)
                  FilledButton.icon(
                    onPressed: isBusy ? null : onValidatePin,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    icon: const Icon(Icons.pin_outlined, size: 18),
                    label: const Text('Validasi PIN'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
