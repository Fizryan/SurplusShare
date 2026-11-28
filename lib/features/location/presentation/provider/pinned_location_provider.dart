import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';
import 'package:surplus_share/features/location/data/pinned_location_repository.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/location_failure.dart';
import 'package:surplus_share/features/location/domain/models/pinned_location.dart';

@immutable
class PinnedLocationState {
  const new({
    this.myLocation,
    this.verifiedRecipients = const <PinnedLocation>[],
    this.isLoading = false,
    this.failure,
  });

  final PinnedLocation? myLocation;
  final List<PinnedLocation> verifiedRecipients;
  final bool isLoading;
  final LocationFailure? failure;

  PinnedLocationState copyWith({
    PinnedLocation? myLocation,
    bool clearMyLocation = false,
    List<PinnedLocation>? verifiedRecipients,
    bool? isLoading,
    LocationFailure? failure,
    bool clearFailure = false,
  }) {
    return PinnedLocationState(
      myLocation: clearMyLocation ? null : (myLocation ?? this.myLocation),
      verifiedRecipients: verifiedRecipients ?? this.verifiedRecipients,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PinnedLocationState &&
        other.myLocation == myLocation &&
        listEquals(other.verifiedRecipients, verifiedRecipients) &&
        other.isLoading == isLoading &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(
    myLocation,
    Object.hashAll(verifiedRecipients),
    isLoading,
    failure,
  );
}

final pinnedLocationRepositoryProvider = Provider<PinnedLocationRepository>((
  ref,
) {
  final config = ref.watch(apiConfigProvider);
  if (config.isDemoMode) {
    return InMemoryPinnedLocationRepository(clock: ref.watch(clockProvider));
  }
  return RemotePinnedLocationRepository(
    dio: ref.watch(authenticatedDioProvider),
  );
});

final pinnedLocationNotifierProvider =
    NotifierProvider<PinnedLocationNotifier, PinnedLocationState>(
      PinnedLocationNotifier.new,
    );

class PinnedLocationNotifier extends Notifier<PinnedLocationState> {
  @override
  PinnedLocationState build() {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const PinnedLocationState();

    final cached = ref
        .read(cacheStoreProvider)
        .readJson(CacheKeys.pinnedLocationFor(userId));
    if (cached == null) return const PinnedLocationState();
    try {
      return PinnedLocationState(myLocation: PinnedLocation.fromJson(cached));
    } on Object {
      return const PinnedLocationState();
    }
  }

  Future<void> loadMyLocation() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(pinnedLocationRepositoryProvider)
        .getPinnedLocation(userId);
    if (!ref.mounted) return;
    await result.fold<Future<void>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
      },
      (location) async {
        state = state.copyWith(
          isLoading: false,
          myLocation: location,
          clearMyLocation: location == null,
        );
        if (location != null) {
          await ref
              .read(cacheStoreProvider)
              .writeJson(
                CacheKeys.pinnedLocationFor(userId),
                location.toJson(),
              );
        }
      },
    );
  }

  Future<void> loadVerifiedRecipients() async {
    final result = await ref
        .read(pinnedLocationRepositoryProvider)
        .getVerifiedRecipientLocations();
    if (!ref.mounted) return;
    result.fold(
      (failure) => state = state.copyWith(failure: failure),
      (recipients) => state = state.copyWith(
        verifiedRecipients: recipients,
        clearFailure: true,
      ),
    );
  }

  Future<bool> saveMyLocation({
    required String placeName,
    required String address,
    required GeoPoint point,
  }) async {
    final claims = ref.read(currentClaimsProvider);
    final userId = claims?.subject;
    if (claims == null || userId == null) {
      state = state.copyWith(
        failure: const LocationUnknownFailure('Sesi pengguna tidak valid.'),
      );
      return false;
    }

    if (claims.role != AppRole.donorPartner &&
        claims.role != AppRole.verifiedRecipient &&
        claims.role != AppRole.admin) {
      state = state.copyWith(
        failure: const LocationUnknownFailure(
          'Hanya mitra donatur atau penerima terverifikasi yang dapat '
          'menyimpan titik lokasi tetap.',
        ),
      );
      return false;
    }

    final candidate = PinnedLocation(
      ownerId: userId,
      ownerRole: claims.role,
      placeName: placeName.trim(),
      address: address.trim(),
      point: point,
      updatedAt: ref.read(clockProvider)().toUtc(),
    );

    final validationError = candidate.validate();
    if (validationError != null) {
      state = state.copyWith(failure: LocationUnknownFailure(validationError));
      return false;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(pinnedLocationRepositoryProvider)
        .savePinnedLocation(candidate);
    if (!ref.mounted) return false;
    return await result.fold<Future<bool>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (saved) async {
        state = state.copyWith(isLoading: false, myLocation: saved);
        await ref
            .read(cacheStoreProvider)
            .writeJson(CacheKeys.pinnedLocationFor(userId), saved.toJson());
        if (saved.ownerRole == AppRole.verifiedRecipient) {
          await loadVerifiedRecipients();
        }
        return true;
      },
    );
  }
}
