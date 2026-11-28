import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';

enum NotificationTriggerReason { favoritePartner, withinRadius, both }

@immutable
class RadiusNotificationEvent {
  const new({
    required this.id,
    required this.listing,
    required this.reason,
    required this.title,
    required this.body,
    required this.triggeredAt,
    this.distanceKm,
  });

  final String id;
  final SurplusListing listing;
  final double? distanceKm;
  final NotificationTriggerReason reason;
  final String title;
  final String body;
  final DateTime triggeredAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RadiusNotificationEvent &&
        other.id == id &&
        other.listing == listing &&
        other.distanceKm == distanceKm &&
        other.reason == reason &&
        other.title == title &&
        other.body == body &&
        other.triggeredAt == triggeredAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, listing, distanceKm, reason, title, body, triggeredAt);
}
