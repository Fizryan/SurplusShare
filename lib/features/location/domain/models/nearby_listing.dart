import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';

@immutable
class NearbyListing {
  const new({
    required this.listing,
    required this.distanceKm,
    required this.isFavoritePartner,
  });

  final SurplusListing listing;
  final double distanceKm;
  final bool isFavoritePartner;

  /// Human-friendly distance label (`850 m` under 1 km, `1.4 km` otherwise).
  String get formattedDistance {
    if (distanceKm < 1) {
      final meters = (distanceKm * 1000).round();
      return '$meters m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NearbyListing &&
        other.listing == listing &&
        other.distanceKm == distanceKm &&
        other.isFavoritePartner == isFavoritePartner;
  }

  @override
  int get hashCode => Object.hash(listing, distanceKm, isFavoritePartner);
}
