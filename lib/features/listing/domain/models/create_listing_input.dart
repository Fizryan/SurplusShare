import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';

@immutable
class CreateListingInput {
  const new({
    required this.partnerId,
    required this.partnerName,
    required this.title,
    required this.description,
    required this.channel,
    required this.originalPrice,
    required this.discountedPrice,
    required this.quantity,
    required this.pickupStart,
    required this.pickupEnd,
    this.volunteerAllocatedPortions = 0,
    this.discountFormat,
    this.location,
    this.address,
    this.foodSafety,
  });

  static const int minDiscountPercent = 10;
  static const int maxDiscountPercent = 90;

  final String partnerId;
  final String partnerName;
  final String title;
  final String description;
  final ListingChannel channel;
  final DiscountFormat? discountFormat;
  final int originalPrice;
  final int discountedPrice;
  final int quantity;
  final int volunteerAllocatedPortions;
  final DateTime pickupStart;
  final DateTime pickupEnd;
  final GeoPoint? location;
  final String? address;
  final FoodSafetyDeclaration? foodSafety;

  PickupWindow get pickupWindow =>
      PickupWindow(start: pickupStart.toUtc(), end: pickupEnd.toUtc());

  /// Validates business rules for both Discount and Donation channels,
  /// including food-safety pickup window bounds.
  String? validate({DateTime? now}) {
    if (partnerId.trim().isEmpty || partnerName.trim().isEmpty) {
      return 'Identitas mitra tidak valid.';
    }
    if (title.trim().isEmpty) {
      return 'Judul stok makanan tidak boleh kosong.';
    }
    if (description.trim().isEmpty) {
      return 'Deskripsi stok makanan tidak boleh kosong.';
    }
    if (quantity <= 0) {
      return 'Jumlah stok harus lebih dari 0.';
    }
    if (volunteerAllocatedPortions < 0 ||
        volunteerAllocatedPortions > quantity) {
      return 'Alokasi porsi relawan harus berada di antara 0 hingga '
          '$quantity porsi.';
    }

    final windowError = pickupWindow.validate(now: now);
    if (windowError != null) return windowError;

    if (location != null && !location!.isValid) {
      return 'Koordinat lokasi mitra tidak valid.';
    }

    if (foodSafety != null) {
      final safetyError = foodSafety!.validate(
        pickupWindow: pickupWindow,
        now: now,
      );
      if (safetyError != null) return safetyError;
    }

    switch (channel) {
      case ListingChannel.discount:
        if (originalPrice <= 0) {
          return 'Harga asli harus lebih dari 0.';
        }
        if (discountFormat == null) {
          return 'Format diskon (Flash Sale / Surprise Bag) wajib dipilih.';
        }
        if (discountedPrice <= 0 || discountedPrice >= originalPrice) {
          return 'Harga diskon harus lebih besar dari 0 dan di bawah harga '
              'asli.';
        }
        final percent = SurplusListing.calculateDiscountPercent(
          originalPrice: originalPrice,
          discountedPrice: discountedPrice,
        );
        if (percent < minDiscountPercent || percent > maxDiscountPercent) {
          return 'Persentase diskon harus berada di antara '
              '$minDiscountPercent% hingga $maxDiscountPercent%.';
        }
      case ListingChannel.donation:
        if (originalPrice < 0) {
          return 'Harga asli tidak boleh negatif.';
        }
        if (discountedPrice != 0) {
          return 'Mode Donasi Gratis wajib memiliki harga 0.';
        }
        if (discountFormat != null) {
          return 'Mode Donasi Gratis tidak menggunakan format diskon.';
        }
    }

    return null;
  }
}
