import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/kyc/data/kyc_repository.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_document.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_failure.dart';
import 'package:surplus_share/features/kyc/domain/models/recipient_category.dart';
import 'package:surplus_share/features/kyc/domain/models/submit_kyc_input.dart';
import 'package:surplus_share/features/kyc/domain/policy/kyc_quota_policy.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';

class _InMemoryTokenStorage implements TokenStorage {
  AuthTokens? _tokens;

  @override
  Future<void> clearTokens() async => _tokens = null;

  @override
  Future<String?> getAccessToken() async => _tokens?.accessToken;

  @override
  Future<AuthTokens?> getTokens() async => _tokens;

  @override
  Future<void> saveTokens(AuthTokens tokens) async => _tokens = tokens;
}

const _validLegalDoc = KycDocument(
  type: KycDocumentType.legalCertificate,
  fileName: 'sk_yayasan.pdf',
  filePath: '/docs/sk_yayasan.pdf',
  mimeType: 'application/pdf',
  fileSizeBytes: 1024 * 500,
);

const _validRecommendationDoc = KycDocument(
  type: KycDocumentType.officialRecommendationLetter,
  fileName: 'surat_rt.pdf',
  filePath: '/docs/surat_rt.pdf',
  mimeType: 'application/pdf',
  fileSizeBytes: 1024 * 300,
);

const _validIdCardDoc = KycDocument(
  type: KycDocumentType.representativeIdCard,
  fileName: 'ktp.jpg',
  filePath: '/docs/ktp.jpg',
  mimeType: 'image/jpeg',
  fileSizeBytes: 1024 * 200,
);

void main() {
  group('KycDocument & SubmitKycInput validation', () {
    test('rejects invalid MIME type and files exceeding 5 MB', () {
      const badMime = KycDocument(
        type: KycDocumentType.legalCertificate,
        fileName: 'malware.exe',
        filePath: '/docs/malware.exe',
        mimeType: 'application/octet-stream',
        fileSizeBytes: 1024,
      );
      const tooLarge = KycDocument(
        type: KycDocumentType.legalCertificate,
        fileName: 'huge.pdf',
        filePath: '/docs/huge.pdf',
        mimeType: 'application/pdf',
        fileSizeBytes: KycDocument.maxFileSizeBytes + 1,
      );

      expect(badMime.validate(), isNotNull);
      expect(tooLarge.validate(), isNotNull);
    });

    test('enforces required documents per category and blocks duplicates', () {
      const missingLegal = SubmitKycInput(
        userId: 'u1',
        organizationName: 'Panti Kasih',
        category: RecipientCategory.orphanage,
        address: 'Jl. Melati 1',
        contactPhone: '081234567890',
        beneficiaryCount: 25,
        documents: [_validIdCardDoc],
      );
      const duplicateDocs = SubmitKycInput(
        userId: 'u1',
        organizationName: 'Relawan Berbagi',
        category: RecipientCategory.distributionVolunteer,
        address: 'Jl. Melati 2',
        contactPhone: '081234567890',
        beneficiaryCount: 15,
        documents: [
          _validRecommendationDoc,
          _validRecommendationDoc,
          _validIdCardDoc,
        ],
      );
      const validVolunteer = SubmitKycInput(
        userId: 'u1',
        organizationName: 'Relawan Berbagi',
        category: RecipientCategory.distributionVolunteer,
        address: 'Jl. Melati 2',
        contactPhone: '081234567890',
        beneficiaryCount: 15,
        documents: [_validRecommendationDoc, _validIdCardDoc],
      );

      expect(missingLegal.validate(), isNotNull);
      expect(duplicateDocs.validate(), isNotNull);
      expect(validVolunteer.validate(), isNull);
    });

    test(
      'calculates safe recommended daily quota clamped to category bounds',
      () {
        expect(
          KycQuotaPolicy.recommendedDailyQuota(
            category: RecipientCategory.orphanage,
            beneficiaryCount: 250,
          ),
          100,
        );
        expect(
          KycQuotaPolicy.recommendedDailyQuota(
            category: RecipientCategory.distributionVolunteer,
            beneficiaryCount: 2,
          ),
          5,
        );
        expect(
          KycQuotaPolicy.recommendedDailyQuota(
            category: RecipientCategory.socialFoundation,
            beneficiaryCount: 45,
          ),
          45,
        );
      },
    );
  });

  group('KYC lifecycle, RBAC review & Daily Quota reset', () {
    test('submit -> block double submit -> admin reject -> resubmit -> admin '
        'approve -> daily quota consumes and auto-resets next day', () async {
      var now = DateTime.utc(2026, 11, 27, 10);
      final tokenStorage = _InMemoryTokenStorage();
      final kycRepo = InMemoryKycRepository(seed: const [], clock: () => now);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          tokenStorageProvider.overrideWithValue(tokenStorage),
          authRepositoryProvider.overrideWithValue(
            DummyAuthRepository(tokenStorage: tokenStorage),
          ),
          kycRepositoryProvider.overrideWithValue(kycRepo),
        ],
      );
      addTearDown(container.dispose);

      // 1. Consumer submits KYC application for an orphanage.
      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);

      final input = SubmitKycInput(
        userId: DummyAuthAccounts.consumer.id,
        organizationName: 'Panti Asuhan Pelita',
        category: RecipientCategory.orphanage,
        registrationNumber: 'AHU-999',
        address: 'Jl. Pelita No. 5',
        contactPhone: '081234567890',
        beneficiaryCount: 20,
        documents: const [_validLegalDoc, _validIdCardDoc],
      );

      expect(
        await container.read(kycNotifierProvider.notifier).submitKyc(input),
        isTrue,
      );
      final firstApp = container.read(kycNotifierProvider).application!;
      expect(firstApp.status, KycStatus.pending);

      // 2. Duplicate submit while pending is rejected.
      expect(
        await container.read(kycNotifierProvider.notifier).submitKyc(input),
        isFalse,
      );
      expect(
        container.read(kycNotifierProvider).failure,
        isA<KycAlreadySubmittedFailure>(),
      );

      // 3. Non-admin cannot approve KYC.
      expect(
        await container
            .read(kycNotifierProvider.notifier)
            .approveKyc(applicationId: firstApp.id, dailyQuota: 20),
        isFalse,
      );
      expect(
        container.read(kycNotifierProvider).failure,
        isA<KycPermissionDeniedFailure>(),
      );

      // 4. Admin rejects with reason -> user can resubmit.
      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.admin.id);
      await container
          .read(kycNotifierProvider.notifier)
          .loadPendingApplications();
      expect(container.read(kycNotifierProvider).pendingApplications.length, 1);

      expect(
        await container
            .read(kycNotifierProvider.notifier)
            .rejectKyc(applicationId: firstApp.id, reason: 'Foto KTP buram'),
        isTrue,
      );

      // 5. User resubmits and Admin approves with 20 portions/day.
      expect(
        await container.read(kycNotifierProvider.notifier).submitKyc(input),
        isTrue,
      );
      final secondApp = container.read(kycNotifierProvider).application!;

      // Out-of-bounds quota (> 100) is rejected.
      expect(
        await container
            .read(kycNotifierProvider.notifier)
            .approveKyc(applicationId: secondApp.id, dailyQuota: 500),
        isFalse,
      );

      expect(
        await container
            .read(kycNotifierProvider.notifier)
            .approveKyc(applicationId: secondApp.id, dailyQuota: 20),
        isTrue,
      );

      // 6. Consume quota: 12 ok, 10 exceeds remaining 8 -> fails.
      final c1 = await kycRepo.consumeDailyQuota(
        userId: DummyAuthAccounts.consumer.id,
        quantity: 12,
      );
      expect(c1.isRight(), isTrue);
      c1.fold((_) {}, (q) => expect(q.remaining, 8));

      final c2 = await kycRepo.consumeDailyQuota(
        userId: DummyAuthAccounts.consumer.id,
        quantity: 10,
      );
      expect(c2.isLeft(), isTrue);
      c2.fold(
        (f) => expect(
          f,
          const DailyQuotaExceededFailure(remaining: 8, dailyLimit: 20),
        ),
        (_) => fail('Expected Left'),
      );

      // 7. Advance clock to next day -> quota automatically resets to 20.
      now = DateTime.utc(2026, 11, 28, 1);
      final nextDayQuota = await kycRepo.getDailyQuota(
        DummyAuthAccounts.consumer.id,
      );
      nextDayQuota.fold((_) => fail('Expected Right'), (q) {
        expect(q.usedToday, 0);
        expect(q.remaining, 20);
      });
    });
  });
}
