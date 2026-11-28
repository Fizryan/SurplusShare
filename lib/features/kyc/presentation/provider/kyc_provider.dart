import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';
import 'package:surplus_share/features/kyc/data/kyc_document_service.dart';
import 'package:surplus_share/features/kyc/data/kyc_repository.dart';
import 'package:surplus_share/features/kyc/data/remote_kyc_repository.dart';
import 'package:surplus_share/features/kyc/domain/models/daily_donation_quota.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_application.dart';
import 'package:surplus_share/features/kyc/domain/models/kyc_failure.dart';
import 'package:surplus_share/features/kyc/domain/models/submit_kyc_input.dart';
import 'package:surplus_share/features/kyc/domain/policy/kyc_quota_policy.dart';

@immutable
class KycState {
  const new({
    this.application,
    this.dailyQuota,
    this.pendingApplications = const <KycApplication>[],
    this.isLoading = false,
    this.failure,
  });

  final KycApplication? application;
  final DailyDonationQuota? dailyQuota;
  final List<KycApplication> pendingApplications;
  final bool isLoading;
  final KycFailure? failure;

  KycState copyWith({
    KycApplication? application,
    bool clearApplication = false,
    DailyDonationQuota? dailyQuota,
    bool clearDailyQuota = false,
    List<KycApplication>? pendingApplications,
    bool? isLoading,
    KycFailure? failure,
    bool clearFailure = false,
  }) {
    return KycState(
      application: clearApplication ? null : (application ?? this.application),
      dailyQuota: clearDailyQuota ? null : (dailyQuota ?? this.dailyQuota),
      pendingApplications: pendingApplications ?? this.pendingApplications,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KycState &&
        other.application == application &&
        other.dailyQuota == dailyQuota &&
        listEquals(other.pendingApplications, pendingApplications) &&
        other.isLoading == isLoading &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(
    application,
    dailyQuota,
    Object.hashAll(pendingApplications),
    isLoading,
    failure,
  );
}

final kycDocumentServiceProvider = Provider<KycDocumentService>((ref) {
  final config = ref.watch(apiConfigProvider);
  if (config.isDemoMode) {
    return DemoKycDocumentService();
  }
  return RemoteKycDocumentService(dio: ref.watch(authenticatedDioProvider));
});

final kycRepositoryProvider = Provider<KycRepository>((ref) {
  final config = ref.watch(apiConfigProvider);
  if (config.isDemoMode) {
    final clock = ref.watch(clockProvider);
    return InMemoryKycRepository(clock: clock);
  }
  return RemoteKycRepository(dio: ref.watch(authenticatedDioProvider));
});

final kycNotifierProvider = NotifierProvider<KycNotifier, KycState>(
  KycNotifier.new,
);

final dailyQuotaProvider = Provider<DailyDonationQuota?>((ref) {
  return ref.watch(kycNotifierProvider.select((state) => state.dailyQuota));
});

class KycNotifier extends Notifier<KycState> {
  @override
  KycState build() {
    // Watching currentUserIdProvider guarantees full state reset on logout or
    // account switch, preventing cross-user KYC/quota/admin leakage.
    final userId = ref.watch(currentUserIdProvider);
    return KycState(dailyQuota: _hydrateCachedQuota(userId));
  }

  Future<void> loadMyKyc() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      state = const KycState();
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final repo = ref.read(kycRepositoryProvider);
    final appResult = await repo.getApplicationForUser(userId);
    if (!ref.mounted) return;

    await appResult.fold<Future<void>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
      },
      (app) async {
        if (app == null || !app.isApproved) {
          state = state.copyWith(
            isLoading: false,
            application: app,
            clearApplication: app == null,
            clearDailyQuota: true,
          );
          _clearCachedQuota(userId);
          return;
        }

        final quotaResult = await repo.getDailyQuota(userId);
        if (!ref.mounted) return;
        state = quotaResult.fold(
          (failure) => state.copyWith(
            isLoading: false,
            application: app,
            failure: failure,
          ),
          (quota) {
            _persistQuota(userId, quota);
            return state.copyWith(
              isLoading: false,
              application: app,
              dailyQuota: quota,
            );
          },
        );
      },
    );
  }

  Future<bool> submitKyc(SubmitKycInput input) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(kycRepositoryProvider)
        .submitApplication(input);
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (submitted) {
        state = state.copyWith(
          isLoading: false,
          application: submitted,
          clearDailyQuota: true,
        );
        return true;
      },
    );
  }

  Future<void> loadPendingApplications() async {
    if (!_canReviewKyc()) {
      state = state.copyWith(failure: const KycPermissionDeniedFailure());
      return;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(kycRepositoryProvider)
        .getPendingApplications();
    if (!ref.mounted) return;
    state = result.fold(
      (failure) => state.copyWith(isLoading: false, failure: failure),
      (pending) =>
          state.copyWith(isLoading: false, pendingApplications: pending),
    );
  }

  Future<bool> approveKyc({
    required String applicationId,
    required int dailyQuota,
  }) async {
    final reviewerId = ref.read(currentUserIdProvider);
    if (reviewerId == null || !_canReviewKyc()) {
      state = state.copyWith(failure: const KycPermissionDeniedFailure());
      return false;
    }
    if (state.isLoading) return false;

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(kycRepositoryProvider)
        .approveApplication(
          applicationId: applicationId,
          reviewerId: reviewerId,
          dailyQuota: dailyQuota,
        );
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (approved) {
        final remainingPending = state.pendingApplications
            .where((app) => app.id != approved.id)
            .toList(growable: false);
        state = state.copyWith(
          isLoading: false,
          pendingApplications: remainingPending,
          application: state.application?.id == approved.id
              ? approved
              : state.application,
        );
        return true;
      },
    );
  }

  Future<bool> rejectKyc({
    required String applicationId,
    required String reason,
  }) async {
    final reviewerId = ref.read(currentUserIdProvider);
    if (reviewerId == null || !_canReviewKyc()) {
      state = state.copyWith(failure: const KycPermissionDeniedFailure());
      return false;
    }
    if (state.isLoading) return false;

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(kycRepositoryProvider)
        .rejectApplication(
          applicationId: applicationId,
          reviewerId: reviewerId,
          reason: reason,
        );
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (rejected) {
        final remainingPending = state.pendingApplications
            .where((app) => app.id != rejected.id)
            .toList(growable: false);
        state = state.copyWith(
          isLoading: false,
          pendingApplications: remainingPending,
          application: state.application?.id == rejected.id
              ? rejected
              : state.application,
        );
        return true;
      },
    );
  }

  void syncDailyQuota(DailyDonationQuota quota) {
    _persistQuota(quota.userId, quota);
    state = state.copyWith(dailyQuota: quota);
  }

  DailyDonationQuota? _hydrateCachedQuota(String? userId) {
    if (userId == null) return null;
    final raw = ref
        .read(cacheStoreProvider)
        .readJson(CacheKeys.dailyQuotaFor(userId));
    if (raw == null) return null;
    final quota = DailyDonationQuota.fromJson(raw);
    final todayKey = DailyDonationQuota.dateKeyFor(ref.read(clockProvider)());
    if (quota.userId != userId || quota.dateKey != todayKey) {
      return null;
    }
    return quota;
  }

  void _persistQuota(String userId, DailyDonationQuota quota) {
    unawaited(
      ref
          .read(cacheStoreProvider)
          .writeJson(
            CacheKeys.dailyQuotaFor(userId),
            quota.toJson(),
            ttl: const Duration(hours: 24),
          ),
    );
  }

  void _clearCachedQuota(String userId) {
    unawaited(
      ref.read(cacheStoreProvider).delete(CacheKeys.dailyQuotaFor(userId)),
    );
  }

  bool _canReviewKyc() {
    final permissions = ref.read(currentPermissionProvider);
    return KycQuotaPolicy.canReviewKyc(permissions);
  }
}
