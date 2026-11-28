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
    String? currentUserId,
    AppRole? role,
  }) {
    return listings
        .where((listing) {
          if (channelFilter != null && listing.channel != channelFilter) {
            return false;
          }
          if (canClaimChannel(
            listing,
            permissions,
            currentUserId: currentUserId,
          )) {
            return true;
          }
          if (role != null &&
              canManage(
                listing,
                currentUserId: currentUserId,
                role: role,
                permissions: permissions,
              )) {
            return true;
          }
          return false;
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

  /// Checks whether the actor has permission to book/claim [listing]'s channel
  /// and is not the owning partner trying to book their own stock.
  static bool canClaimChannel(
    SurplusListing listing,
    Set<Permission> permissions, {
    String? currentUserId,
  }) {
    if (currentUserId != null && listing.partnerId == currentUserId) {
      return false;
    }
    return switch (listing.channel) {
      ListingChannel.discount => permissions.contains(
        Permission.browseDiscountListings,
      ),
      ListingChannel.donation => permissions.contains(
        Permission.claimDonationListings,
      ),
    };
  }

  static bool canClaim(
    SurplusListing listing,
    Set<Permission> permissions, {
    DateTime? now,
    String? currentUserId,
  }) {
    if (!listing.isAvailable(now: now)) return false;
    return canClaimChannel(listing, permissions, currentUserId: currentUserId);
  }
}
