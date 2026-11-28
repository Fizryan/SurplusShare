import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/core/shared/widgets/app_status_chip.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/auth/presentation/widgets/auth_submit_button.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/presentation/helpers/reservation_action_helper.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';

/// Compact bottom sheet allowing recipients to claim multiple donation
/// portions (bounded by daily quota) and consumers to pick discount quantity
/// and payment method.
class BookListingSheet extends ConsumerStatefulWidget {
  const new({required this.listing, super.key});

  final SurplusListing listing;

  @override
  ConsumerState<BookListingSheet> createState() => _BookListingSheetState();
}

class _BookListingSheetState extends ConsumerState<BookListingSheet> {
  static const int _maxDiscountPerOrder = 10;

  int _quantity = 1;
  PaymentMethod _paymentMethod = PaymentMethod.qris;

  int _resolveMaxQuantity({
    required bool isDonation,
    required bool isAdmin,
    required int? quotaRemaining,
  }) {
    final stock = widget.listing.remainingQuantity;
    if (stock <= 0) return 0;
    if (!isDonation) {
      return math.min(stock, _maxDiscountPerOrder);
    }
    if (isAdmin || quotaRemaining == null) return stock;
    return math.min(stock, math.max(0, quotaRemaining));
  }

  Future<void> _submit(int maxQty) async {
    if (maxQty <= 0) return;
    final clampedQty = _quantity.clamp(1, maxQty);
    final ok = await bookOrClaimListing(
      ref,
      widget.listing,
      quantity: clampedQty,
      paymentMethod: _paymentMethod,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDonation = widget.listing.channel == ListingChannel.donation;
    final role = ref.watch(currentClaimsProvider)?.role;
    final isAdmin = role == AppRole.admin;
    final dailyQuota = ref.watch(dailyQuotaProvider);
    final isBusy = ref.watch(
      reservationNotifierProvider.select((s) => s.isLoading),
    );

    final maxQty = _resolveMaxQuantity(
      isDonation: isDonation,
      isAdmin: isAdmin,
      quotaRemaining: dailyQuota?.remaining,
    );
    final effectiveQty = maxQty == 0 ? 0 : _quantity.clamp(1, maxQty);
    final totalPrice = effectiveQty * widget.listing.discountedPrice;

    final quickOptions = <int>{
      if (maxQty >= 1) 1,
      if (maxQty >= 5) 5,
      if (maxQty >= 10) 10,
      if (maxQty > 1) maxQty,
    }.toList()..sort();

    return AppBottomSheetScaffold(
      title: isDonation ? 'Klaim Porsi Donasi Gratis' : 'Pesan Paket Surplus',
      subtitle: '${widget.listing.title} • ${widget.listing.partnerName}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppStatusChip(
                label: 'Sisa stok: ${widget.listing.remainingQuantity} porsi',
                icon: Icons.inventory_2_outlined,
              ),
              if (isDonation && dailyQuota != null)
                AppStatusChip(
                  label:
                      'Kuota hari ini: ${dailyQuota.remaining}/'
                      '${dailyQuota.dailyLimit} porsi',
                  icon: Icons.verified_user_outlined,
                  tone: dailyQuota.remaining > 0
                      ? AppChipTone.primary
                      : AppChipTone.error,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (maxQty == 0)
            Text(
              isDonation
                  ? 'Kuota donasi harian Anda hari ini sudah habis atau stok '
                        'tidak tersedia.'
                  : 'Stok makanan sudah tidak tersedia.',
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jumlah Porsi',
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    IconButton.outlined(
                      key: const Key('book_qty_decrement'),
                      onPressed: isBusy || effectiveQty <= 1
                          ? null
                          : () => setState(() => _quantity = effectiveQty - 1),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(
                        '$effectiveQty',
                        key: const Key('book_qty_value'),
                        style: textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      key: const Key('book_qty_increment'),
                      onPressed: isBusy || effectiveQty >= maxQty
                          ? null
                          : () => setState(() => _quantity = effectiveQty + 1),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ],
            ),
            if (quickOptions.length > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final option in quickOptions)
                    ChoiceChip(
                      key: Key('book_qty_chip_$option'),
                      label: Text(
                        option == maxQty && option > 1
                            ? 'Maks ($option)'
                            : '$option porsi',
                      ),
                      selected: effectiveQty == option,
                      onSelected: isBusy
                          ? null
                          : (_) => setState(() => _quantity = option),
                    ),
                ],
              ),
            ],
            if (!isDonation) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Metode Pembayaran',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<PaymentMethod>(
                segments: const [
                  ButtonSegment(
                    value: PaymentMethod.qris,
                    label: Text('QRIS'),
                    icon: Icon(Icons.qr_code_2_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.eWallet,
                    label: Text('E-Wallet'),
                    icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
                  ),
                ],
                selected: {_paymentMethod},
                onSelectionChanged: isBusy
                    ? null
                    : (s) => setState(() => _paymentMethod = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Pembayaran',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    AppFormatters.formatRupiah(totalPrice),
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AuthSubmitButton(
              key: const Key('book_listing_confirm_button'),
              label: isDonation
                  ? 'Klaim $effectiveQty Porsi Gratis'
                  : 'Pesan $effectiveQty Porsi • '
                        '${AppFormatters.formatRupiah(totalPrice)}',
              isLoading: isBusy,
              onPressed: () => _submit(maxQty),
            ),
          ],
        ],
      ),
    );
  }
}
