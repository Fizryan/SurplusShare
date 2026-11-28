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

    test(
      'donorPartner and partnerStaff require KYC approved to manage stock',
      () {
        for (final role in [AppRole.donorPartner, AppRole.partnerStaff]) {
          final unverified = PermissionPolicy.resolve(
            role: role,
            kycStatus: KycStatus.pending,
          );
          expect(unverified.contains(Permission.createListing), isFalse);
          expect(unverified.contains(Permission.manageListing), isFalse);

          final approved = PermissionPolicy.resolve(
            role: role,
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
        }
      },
    );

    test('admin receives all permissions', () {
      final perms = PermissionPolicy.resolve(
        role: AppRole.admin,
        kycStatus: KycStatus.approved,
      );

      expect(perms, equals(Permission.values.toSet()));
    });
  });
}
