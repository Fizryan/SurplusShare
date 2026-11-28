import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';

/// Shared SSOT booking handler used by both FeedScreen and ExploreScreen.
Future<void> bookOrClaimListing(WidgetRef ref, SurplusListing item) async {
  final notifier = ref.read(reservationNotifierProvider.notifier);
  final snack = ref.read(snackbarServiceProvider);

  if (item.channel == ListingChannel.discount) {
    final created = await notifier.bookDiscount(
      listing: item,
      quantity: 1,
      paymentMethod: PaymentMethod.qris,
    );
    if (created != null) {
      snack.showSuccess(
        'Reservasi dibuat. Selesaikan pembayaran di tab Reservasi.',
      );
    } else {
      final err = ref.read(reservationNotifierProvider).failure;
      if (err != null) snack.showError(err.message);
    }
    return;
  }

  final created = await notifier.bookDonation(listing: item, quantity: 1);
  if (created != null) {
    snack.showSuccess('Donasi diklaim! PIN: ${created.pickupPin}');
  } else {
    final err = ref.read(reservationNotifierProvider).failure;
    if (err != null) snack.showError(err.message);
  }
}
