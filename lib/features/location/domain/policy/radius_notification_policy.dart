import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/domain/policy/listing_access_policy.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/nearby_listing.dart';
import 'package:surplus_share/features/location/domain/models/radius_notification_event.dart';

/// Pure domain rules for nearby search (1–3 km) and real-time surplus alerts.
abstract final class RadiusNotificationPolicy {
  static const double minRadiusKm = 1;
  static const double maxRadiusKm = 3;
  static const double defaultRadiusKm = 2;

  static double clampRadiusKm(double radiusKm) {
    return radiusKm.clamp(minRadiusKm, maxRadiusKm);
  }

  /// Filters available, permission-visible listings within [radiusKm] of
  /// [userLocation] and sorts nearest first.
  static List<NearbyListing> findNearby({
    required Iterable<SurplusListing> listings,
    required GeoPoint userLocation,
    required double radiusKm,
    required Set<String> favoritePartnerIds,
    required Set<Permission> permissions,
    DateTime? now,
  }) {
    final effectiveRadius = clampRadiusKm(radiusKm);
    final results = <NearbyListing>[];

    for (final listing in listings) {
      final loc = listing.location;
      if (loc == null) continue;
      if (!listing.isAvailable(now: now)) continue;
      if (!ListingAccessPolicy.canView(listing, permissions)) continue;

      final distance = userLocation.distanceInKmTo(loc);
      if (distance <= effectiveRadius) {
        results.add(
          NearbyListing(
            listing: listing,
            distanceKm: distance,
            isFavoritePartner: favoritePartnerIds.contains(listing.partnerId),
          ),
        );
      }
    }

    results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return List<NearbyListing>.unmodifiable(results);
  }

  /// Evaluates whether a newly published [listing] should trigger a real-time
  /// push notification for the current user.
  ///
  /// Strictly enforces [ListingAccessPolicy.canView] so unverified accounts
  /// never receive Donation-channel notifications.
  static RadiusNotificationEvent? evaluateNewListingNotification({
    required SurplusListing listing,
    required GeoPoint? userLocation,
    required double radiusKm,
    required Set<String> favoritePartnerIds,
    required Set<Permission> permissions,
    required DateTime now,
  }) {
    if (!listing.isAvailable(now: now)) return null;
    if (!ListingAccessPolicy.canView(listing, permissions)) return null;

    final isFavorite = favoritePartnerIds.contains(listing.partnerId);
    final effectiveRadius = clampRadiusKm(radiusKm);
    final distance = (userLocation != null && listing.location != null)
        ? userLocation.distanceInKmTo(listing.location!)
        : null;
    final inRadius = distance != null && distance <= effectiveRadius;

    if (!isFavorite && !inRadius) return null;

    final reason = switch ((isFavorite, inRadius)) {
      (true, true) => NotificationTriggerReason.both,
      (true, false) => NotificationTriggerReason.favoritePartner,
      (false, true) => NotificationTriggerReason.withinRadius,
      (false, false) => throw StateError('unreachable'),
    };

    final channelLabel = listing.channel == ListingChannel.donation
        ? 'Donasi Gratis'
        : 'Diskon ${listing.discountPercent}%';
    final distanceLabel = distance == null
        ? ''
        : distance < 1
        ? ' (${(distance * 1000).round()} m dari Anda)'
        : ' (${distance.toStringAsFixed(1)} km dari Anda)';

    return RadiusNotificationEvent(
      id: 'notif-${listing.id}-${now.millisecondsSinceEpoch}',
      listing: listing,
      distanceKm: distance,
      reason: reason,
      title: isFavorite
          ? 'Mitra Favorit: ${listing.partnerName}'
          : 'Stok Surplus Terdekat: ${listing.partnerName}',
      body:
          '${listing.title} ($channelLabel) tersedia '
          '${listing.remainingQuantity} porsi$distanceLabel.',
      triggeredAt: now.toUtc(),
    );
  }
}
