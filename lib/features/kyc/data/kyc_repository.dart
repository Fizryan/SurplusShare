import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/kyc/domain/models/daily_donation_quota.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_application.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_document.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_failure.dart';
import 'package:surplus_share/features/kyc/domain/models/recipient_category.dart';
import 'package:surplus_share/features/kyc/domain/models/submit_kyc_input.dart';
import 'package:surplus_share/features/kyc/domain/policy/kyc_quota_policy.dart';
import 'package:uuid/uuid.dart';

abstract interface class KycRepository {
  Future<Either<KycFailure, KycApplication?>> getApplicationForUser(
    String userId,
  );

  Future<Either<KycFailure, List<KycApplication>>> getPendingApplications();

  Future<Either<KycFailure, KycApplication>> submitApplication(
    SubmitKycInput input,
  );

  Future<Either<KycFailure, KycApplication>> approveApplication({
    required String applicationId,
    required String reviewerId,
    required int dailyQuota,
  });

  Future<Either<KycFailure, KycApplication>> rejectApplication({
    required String applicationId,
    required String reviewerId,
    required String reason,
  });

  Future<Either<KycFailure, DailyDonationQuota>> getDailyQuota(String userId);

  Future<Either<KycFailure, DailyDonationQuota>> consumeDailyQuota({
    required String userId,
    required int quantity,
  });

  Future<Either<KycFailure, DailyDonationQuota>> refundDailyQuota({
    required String userId,
    required int quantity,
  });
}

class InMemoryKycRepository implements KycRepository {
  new({List<KycApplication>? seed, Uuid? uuid, Clock? clock})
    : _clock = clock ?? DateTime.now,
      _uuid = uuid ?? const Uuid(),
      _applications = List<KycApplication>.of(
        seed ?? _defaultSeed((clock ?? DateTime.now)()),
      );

  final List<KycApplication> _applications;
  final Map<String, DailyDonationQuota> _quotas = {};
  final Uuid _uuid;
  final Clock _clock;

  @override
  Future<Either<KycFailure, KycApplication?>> getApplicationForUser(
    String userId,
  ) async {
    return right(_findLatestForUser(userId));
  }

  @override
  Future<Either<KycFailure, List<KycApplication>>>
  getPendingApplications() async {
    final pending = _applications
        .where((app) => app.status == KycStatus.pending)
        .toList(growable: false);
    return right(List<KycApplication>.unmodifiable(pending));
  }

  @override
  Future<Either<KycFailure, KycApplication>> submitApplication(
    SubmitKycInput input,
  ) async {
    final validationError = input.validate();
    if (validationError != null) {
      return left(KycValidationFailure(validationError));
    }

    final existing = _findLatestForUser(input.userId.trim());
    if (existing != null && !existing.canResubmit) {
      return left(const KycAlreadySubmittedFailure());
    }

    final now = _clock().toUtc();
    final application = KycApplication(
      id: _uuid.v4(),
      userId: input.userId.trim(),
      organizationName: input.organizationName.trim(),
      category: input.category,
      registrationNumber: input.registrationNumber?.trim(),
      address: input.address.trim(),
      contactPhone: input.contactPhone.trim(),
      beneficiaryCount: input.beneficiaryCount,
      documents: List<KycDocument>.unmodifiable(input.documents),
      status: KycStatus.pending,
      submittedAt: now,
    );

    _applications.insert(0, application);
    return right(application);
  }

  @override
  Future<Either<KycFailure, KycApplication>> approveApplication({
    required String applicationId,
    required String reviewerId,
    required int dailyQuota,
  }) async {
    final index = _applications.indexWhere((a) => a.id == applicationId);
    if (index == -1) {
      return left(const KycNotFoundFailure());
    }

    final current = _applications[index];
    if (!current.isPending) {
      return left(
        const KycInvalidStatusTransitionFailure(
          'Hanya pengajuan berstatus pending yang dapat disetujui.',
        ),
      );
    }

    final quotaError = KycQuotaPolicy.validateApprovedQuota(
      category: current.category,
      dailyQuota: dailyQuota,
    );
    if (quotaError != null) {
      return left(KycValidationFailure(quotaError));
    }

    final now = _clock().toUtc();
    final approved = current.copyWith(
      status: KycStatus.approved,
      approvedDailyQuota: dailyQuota,
      clearRejectionReason: true,
      reviewedAt: now,
      reviewedBy: reviewerId,
    );
    _applications[index] = approved;

    final dateKey = DailyDonationQuota.dateKeyFor(now);
    _quotas[current.userId] = DailyDonationQuota(
      userId: current.userId,
      dateKey: dateKey,
      dailyLimit: dailyQuota,
      usedToday: 0,
    );

    return right(approved);
  }

  @override
  Future<Either<KycFailure, KycApplication>> rejectApplication({
    required String applicationId,
    required String reviewerId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      return left(const KycValidationFailure('Alasan penolakan wajib diisi.'));
    }

    final index = _applications.indexWhere((a) => a.id == applicationId);
    if (index == -1) {
      return left(const KycNotFoundFailure());
    }

    final current = _applications[index];
    if (!current.isPending) {
      return left(
        const KycInvalidStatusTransitionFailure(
          'Hanya pengajuan berstatus pending yang dapat ditolak.',
        ),
      );
    }

    final rejected = current.copyWith(
      status: KycStatus.rejected,
      clearApprovedDailyQuota: true,
      rejectionReason: reason.trim(),
      reviewedAt: _clock().toUtc(),
      reviewedBy: reviewerId,
    );
    _applications[index] = rejected;
    return right(rejected);
  }

  @override
  Future<Either<KycFailure, DailyDonationQuota>> getDailyQuota(
    String userId,
  ) async {
    final app = _findLatestForUser(userId);
    if (app == null || !app.isApproved || app.approvedDailyQuota == null) {
      return left(
        const KycPermissionDeniedFailure(
          'Akun belum terverifikasi sebagai penerima donasi.',
        ),
      );
    }

    final todayKey = DailyDonationQuota.dateKeyFor(_clock());
    final existing = _quotas[userId];
    if (existing == null || existing.dateKey != todayKey) {
      final fresh = DailyDonationQuota(
        userId: userId,
        dateKey: todayKey,
        dailyLimit: app.approvedDailyQuota!,
        usedToday: 0,
      );
      _quotas[userId] = fresh;
      return right(fresh);
    }

    return right(existing);
  }

  @override
  Future<Either<KycFailure, DailyDonationQuota>> consumeDailyQuota({
    required String userId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      return left(
        const KycValidationFailure('Jumlah porsi klaim harus lebih dari 0.'),
      );
    }

    final quotaResult = await getDailyQuota(userId);
    return quotaResult.flatMap((quota) {
      if (!quota.canClaim(quantity)) {
        return left(
          DailyQuotaExceededFailure(
            remaining: quota.remaining,
            dailyLimit: quota.dailyLimit,
          ),
        );
      }

      final updated = quota.copyWith(usedToday: quota.usedToday + quantity);
      _quotas[userId] = updated;
      return right(updated);
    });
  }

  @override
  Future<Either<KycFailure, DailyDonationQuota>> refundDailyQuota({
    required String userId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      return left(
        const KycValidationFailure('Jumlah refund kuota harus lebih dari 0.'),
      );
    }

    final quotaResult = await getDailyQuota(userId);
    return quotaResult.map((quota) {
      final nextUsed = (quota.usedToday - quantity).clamp(0, quota.dailyLimit);
      final updated = quota.copyWith(usedToday: nextUsed);
      _quotas[userId] = updated;
      return updated;
    });
  }

  KycApplication? _findLatestForUser(String userId) {
    for (final app in _applications) {
      if (app.userId == userId) return app;
    }
    return null;
  }

  static List<KycApplication> _defaultSeed(DateTime referenceTime) {
    final now = referenceTime.toUtc();
    return [
      KycApplication(
        id: 'kyc-recipient-1',
        userId: DummyAuthAccounts.verifiedRecipient.id,
        organizationName: DummyAuthAccounts.verifiedRecipient.displayName,
        category: RecipientCategory.orphanage,
        registrationNumber: 'AHU-0012345.AH.01.04',
        address: 'Jl. Harapan Bangsa No. 12, Jakarta',
        contactPhone: '081234567890',
        beneficiaryCount: 30,
        documents: const [
          KycDocument(
            type: KycDocumentType.legalCertificate,
            fileName: 'akta_yayasan.pdf',
            filePath: '/docs/akta_yayasan.pdf',
            mimeType: 'application/pdf',
            fileSizeBytes: 512000,
          ),
          KycDocument(
            type: KycDocumentType.representativeIdCard,
            fileName: 'ktp_pengurus.jpg',
            filePath: '/docs/ktp_pengurus.jpg',
            mimeType: 'image/jpeg',
            fileSizeBytes: 256000,
          ),
        ],
        status: KycStatus.approved,
        approvedDailyQuota: 30,
        submittedAt: now.subtract(const Duration(days: 7)),
        reviewedAt: now.subtract(const Duration(days: 6)),
        reviewedBy: DummyAuthAccounts.admin.id,
      ),
    ];
  }
}
