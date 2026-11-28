import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';

/// Pure domain access rules for Dual-Channel Listing (Discount & Donation).
abstract final class ListingAccessPolicy {
  static bool canView(SurplusListing listing, Set<Permission> permissions) {
    return switch (listing.channel) {
      ListingChannel.discount => permissions.contains(
        Permission.browseDiscountListings,
      ),
      ListingChannel.donation => permissions.contains(
        Permission.browseDonationListings,
      ),
    };
  }

  static List<SurplusListing> filterVisible(
    Iterable<SurplusListing> listings,
    Set<Permission> permissions, {
    ListingChannel? channelFilter,
  }) {
    return listings
        .where((listing) {
          if (channelFilter != null && listing.channel != channelFilter) {
            return false;
          }
          return canView(listing, permissions);
        })
        .toList(growable: false);
  }

  static bool canCreate(Set<Permission> permissions) {
    return permissions.contains(Permission.createListing);
  }

  static bool canManage(
    SurplusListing listing, {
    required String? currentUserId,
    required AppRole role,
    required Set<Permission> permissions,
  }) {
    if (!permissions.contains(Permission.manageListing)) return false;
    if (role == AppRole.admin) return true;
    return currentUserId != null && listing.partnerId == currentUserId;
  }

  static bool canClaim(
    SurplusListing listing,
    Set<Permission> permissions, {
    DateTime? now,
  }) {
    if (!listing.isAvailable(now: now)) return false;
    return switch (listing.channel) {
      ListingChannel.discount => permissions.contains(
        Permission.browseDiscountListings,
      ),
      ListingChannel.donation => permissions.contains(
        Permission.claimDonationListings,
      ),
    };
  }
}
