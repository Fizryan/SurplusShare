import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';

abstract final class PermissionPolicy {
  static const Map<AppRole, Set<Permission>> _roleDefaults = {
    AppRole.consumer: {Permission.browseDiscountListings},
    AppRole.verifiedRecipient: {Permission.browseDiscountListings},
    AppRole.donorPartner: {Permission.browseDiscountListings},
    AppRole.partnerStaff: {Permission.browseDiscountListings},
    AppRole.admin: {
      Permission.browseDiscountListings,
      Permission.browseDonationListings,
      Permission.claimDonationListings,
      Permission.createListing,
      Permission.manageListing,
      Permission.validatePickupPin,
      Permission.exportCsrReport,
      Permission.reviewKyc,
    },
  };

  static const Map<AppRole, Set<Permission>> _kycApprovedAdditions = {
    AppRole.verifiedRecipient: {
      Permission.browseDonationListings,
      Permission.claimDonationListings,
    },
    AppRole.donorPartner: {
      Permission.createListing,
      Permission.manageListing,
      Permission.validatePickupPin,
      Permission.exportCsrReport,
    },
    AppRole.partnerStaff: {
      Permission.createListing,
      Permission.manageListing,
      Permission.validatePickupPin,
      Permission.exportCsrReport,
    },
  };

  static Set<Permission> defaultsForRole(AppRole role) {
    return Set.unmodifiable(_roleDefaults[role] ?? const <Permission>{});
  }

  static Set<Permission> resolve({
    required AppRole role,
    required KycStatus kycStatus,
    Iterable<Permission> granted = const [],
    Iterable<Permission> revoked = const [],
  }) {
    final resolved = Set<Permission>.from(
      _roleDefaults[role] ?? const <Permission>{},
    );

    if (kycStatus == KycStatus.approved) {
      resolved.addAll(_kycApprovedAdditions[role] ?? const <Permission>{});
    }

    resolved
      ..addAll(granted)
      ..removeAll(revoked);

    return Set.unmodifiable(resolved);
  }

  static bool hasAll(
    Set<Permission> current,
    Set<Permission> requiredPermission,
  ) {
    return current.containsAll(requiredPermission);
  }

  static bool hasAny(Set<Permission> current, Set<Permission> candidates) {
    return candidates.any(current.contains);
  }
}
