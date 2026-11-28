import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_policy.dart';

void main() {
  group('PermissionPolicy RBAC + KYC', () {
    test('consumer only receives browseDiscountListings', () {
      final perms = PermissionPolicy.resolve(
        role: AppRole.consumer,
        kycStatus: KycStatus.approved,
      );

      expect(perms, equals({Permission.browseDiscountListings}));
    });

    test('verifiedRecipient requires KYC approved for donation access', () {
      for (final status in [
        KycStatus.unverified,
        KycStatus.pending,
        KycStatus.rejected,
      ]) {
        final perms = PermissionPolicy.resolve(
          role: AppRole.verifiedRecipient,
          kycStatus: status,
        );
        expect(perms.contains(Permission.browseDonationListings), isFalse);
        expect(perms.contains(Permission.claimDonationListings), isFalse);
      }

      final approved = PermissionPolicy.resolve(
        role: AppRole.verifiedRecipient,
        kycStatus: KycStatus.approved,
      );
      expect(
        approved,
        equals({
          Permission.browseDiscountListings,
          Permission.browseDonationListings,
          Permission.claimDonationListings,
        }),
      );
    });

    test('donorPartner requires KYC approved to manage stock', () {
      final unverified = PermissionPolicy.resolve(
        role: AppRole.donorPartner,
        kycStatus: KycStatus.pending,
      );
      expect(unverified.contains(Permission.createListing), isFalse);
      expect(unverified.contains(Permission.manageListing), isFalse);

      final approved = PermissionPolicy.resolve(
        role: AppRole.donorPartner,
        kycStatus: KycStatus.approved,
      );
      expect(
        approved,
        equals({
          Permission.browseDiscountListings,
          Permission.createListing,
          Permission.manageListing,
          Permission.validatePickupPin,
          Permission.exportCsrReport,
        }),
      );
    });

    test('volunteer requires KYC approved for distribution management', () {
      final pending = PermissionPolicy.resolve(
        role: AppRole.volunteer,
        kycStatus: KycStatus.pending,
      );
      expect(pending, equals({Permission.browseDiscountListings}));

      final approved = PermissionPolicy.resolve(
        role: AppRole.volunteer,
        kycStatus: KycStatus.approved,
      );
      expect(
        approved,
        equals({
          Permission.browseDiscountListings,
          Permission.manageDistribution,
        }),
      );
      expect(approved.contains(Permission.browseDonationListings), isFalse);
      expect(approved.contains(Permission.createListing), isFalse);
      expect(approved.contains(Permission.validatePickupPin), isFalse);
    });

    test('admin receives all permissions', () {
      final perms = PermissionPolicy.resolve(
        role: AppRole.admin,
        kycStatus: KycStatus.approved,
      );

      expect(perms, equals(Permission.values.toSet()));
    });
  });
}
