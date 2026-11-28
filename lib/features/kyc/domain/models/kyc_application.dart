import 'package:flutter/foundation.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_document.dart';
import 'package:surplus_share/features/kyc/domain/models/recipient_category.dart';

@immutable
class KycApplication {
  const new({
    required this.id,
    required this.userId,
    required this.organizationName,
    required this.category,
    required this.address,
    required this.contactPhone,
    required this.beneficiaryCount,
    required this.documents,
    required this.status,
    required this.submittedAt,
    this.registrationNumber,
    this.approvedDailyQuota,
    this.rejectionReason,
    this.reviewedAt,
    this.reviewedBy,
  });

  factory fromJson(Map<String, dynamic> json) {
    final rawCategory = json['category'] as String? ?? '';
    final rawStatus = json['status'] as String? ?? '';
    final rawDocs = json['documents'];
    final rawReviewedAt = json['reviewed_at'] ?? json['reviewedAt'];
    return KycApplication(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? json['userId'] as String? ?? '',
      organizationName:
          json['organization_name'] as String? ??
          json['organizationName'] as String? ??
          '',
      category: RecipientCategory.values.firstWhere(
        (e) => e.name == rawCategory,
        orElse: () => RecipientCategory.orphanage,
      ),
      registrationNumber:
          json['registration_number'] as String? ??
          json['registrationNumber'] as String?,
      address: json['address'] as String? ?? '',
      contactPhone:
          json['contact_phone'] as String? ??
          json['contactPhone'] as String? ??
          '',
      beneficiaryCount:
          (json['beneficiary_count'] as num? ??
                  json['beneficiaryCount'] as num?)
              ?.toInt() ??
          0,
      documents: rawDocs is List
          ? [
              for (final item in rawDocs.whereType<Map<dynamic, dynamic>>())
                KycDocument.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const <KycDocument>[],
      status: KycStatus.values.firstWhere(
        (e) => e.name == rawStatus,
        orElse: () => KycStatus.pending,
      ),
      approvedDailyQuota:
          (json['approved_daily_quota'] as num? ??
                  json['approvedDailyQuota'] as num?)
              ?.toInt(),
      rejectionReason:
          json['rejection_reason'] as String? ??
          json['rejectionReason'] as String?,
      submittedAt: DateTime.parse(
        (json['submitted_at'] ?? json['submittedAt']) as String,
      ).toUtc(),
      reviewedAt: rawReviewedAt is String
          ? DateTime.parse(rawReviewedAt).toUtc()
          : null,
      reviewedBy:
          json['reviewed_by'] as String? ?? json['reviewedBy'] as String?,
    );
  }

  final String id;
  final String userId;
  final String organizationName;
  final RecipientCategory category;
  final String? registrationNumber;
  final String address;
  final String contactPhone;
  final int beneficiaryCount;
  final List<KycDocument> documents;
  final KycStatus status;
  final int? approvedDailyQuota;
  final String? rejectionReason;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  bool get isApproved => status == KycStatus.approved;
  bool get isPending => status == KycStatus.pending;
  bool get canResubmit => status == KycStatus.rejected;

  KycApplication copyWith({
    KycStatus? status,
    int? approvedDailyQuota,
    bool clearApprovedDailyQuota = false,
    String? rejectionReason,
    bool clearRejectionReason = false,
    DateTime? reviewedAt,
    String? reviewedBy,
  }) {
    return KycApplication(
      id: id,
      userId: userId,
      organizationName: organizationName,
      category: category,
      registrationNumber: registrationNumber,
      address: address,
      contactPhone: contactPhone,
      beneficiaryCount: beneficiaryCount,
      documents: documents,
      status: status ?? this.status,
      approvedDailyQuota: clearApprovedDailyQuota
          ? null
          : (approvedDailyQuota ?? this.approvedDailyQuota),
      rejectionReason: clearRejectionReason
          ? null
          : (rejectionReason ?? this.rejectionReason),
      submittedAt: submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KycApplication &&
        other.id == id &&
        other.userId == userId &&
        other.organizationName == organizationName &&
        other.category == category &&
        other.registrationNumber == registrationNumber &&
        other.address == address &&
        other.contactPhone == contactPhone &&
        other.beneficiaryCount == beneficiaryCount &&
        listEquals(other.documents, documents) &&
        other.status == status &&
        other.approvedDailyQuota == approvedDailyQuota &&
        other.rejectionReason == rejectionReason &&
        other.submittedAt == submittedAt &&
        other.reviewedAt == reviewedAt &&
        other.reviewedBy == reviewedBy;
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    organizationName,
    category,
    registrationNumber,
    address,
    contactPhone,
    beneficiaryCount,
    Object.hashAll(documents),
    status,
    approvedDailyQuota,
    rejectionReason,
    submittedAt,
    reviewedAt,
    reviewedBy,
  );
}
