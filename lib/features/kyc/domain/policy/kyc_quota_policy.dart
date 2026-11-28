import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_document.dart';
import 'package:surplus_share/features/kyc/domain/models/recipient_category.dart';

/// Pure domain rules for donation recipient KYC documents and daily quotas.
abstract final class KycQuotaPolicy {
  static Set<KycDocumentType> requiredDocumentsFor(RecipientCategory category) {
    return switch (category) {
      RecipientCategory.orphanage ||
      RecipientCategory.socialFoundation => const {
        KycDocumentType.legalCertificate,
        KycDocumentType.representativeIdCard,
      },
      RecipientCategory.distributionVolunteer => const {
        KycDocumentType.officialRecommendationLetter,
        KycDocumentType.representativeIdCard,
      },
    };
  }

  /// Calculates a safe recommended daily quota (portions/day) clamped to
  /// category limits to prevent abuse.
  static int recommendedDailyQuota({
    required RecipientCategory category,
    required int beneficiaryCount,
  }) {
    final safeCount = beneficiaryCount < 1 ? 1 : beneficiaryCount;
    return safeCount.clamp(category.minDailyQuota, category.maxDailyQuota);
  }

  /// Validates an admin-assigned daily quota against category safety bounds.
  static String? validateApprovedQuota({
    required RecipientCategory category,
    required int dailyQuota,
  }) {
    if (dailyQuota < category.minDailyQuota ||
        dailyQuota > category.maxDailyQuota) {
      return 'Kuota harian untuk kategori ini harus antara '
          '${category.minDailyQuota} hingga ${category.maxDailyQuota} '
          'porsi/hari.';
    }
    return null;
  }

  static bool canReviewKyc(Set<Permission> permissions) {
    return permissions.contains(Permission.reviewKyc);
  }
}
