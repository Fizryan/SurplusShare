import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/widgets/app_bottom_sheet_scaffold.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';
import 'package:surplus_share/features/reservation/presentation/widgets/book_listing_sheet.dart';

/// Opens the SSOT portion picker sheet before booking or claiming [item].
Future<void> showBookListingSheet(BuildContext context, SurplusListing item) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => BookListingSheet(listing: item),
  );
}

/// Shared SSOT booking handler used by both FeedScreen and ExploreScreen.
Future<bool> bookOrClaimListing(
  WidgetRef ref,
  SurplusListing item, {
  int quantity = 1,
  PaymentMethod paymentMethod = PaymentMethod.qris,
}) async {
  final notifier = ref.read(reservationNotifierProvider.notifier);
  final snack = ref.read(snackbarServiceProvider);

  if (item.channel == ListingChannel.discount) {
    final created = await notifier.bookDiscount(
      listing: item,
      quantity: quantity,
      paymentMethod: paymentMethod,
    );
    if (created != null) {
      snack.showSuccess(
        'Reservasi $quantity porsi dibuat. Selesaikan pembayaran di tab '
        'Reservasi.',
      );
      return true;
    }
    final err = ref.read(reservationNotifierProvider).failure;
    if (err != null) snack.showError(err.message);
    return false;
  }

  final created = await notifier.bookDonation(
    listing: item,
    quantity: quantity,
  );
  if (created != null) {
    snack.showSuccess(
      '$quantity porsi donasi diklaim! PIN: ${created.pickupPin}',
    );
    return true;
  }
  final err = ref.read(reservationNotifierProvider).failure;
  if (err != null) snack.showError(err.message);
  return false;
}
