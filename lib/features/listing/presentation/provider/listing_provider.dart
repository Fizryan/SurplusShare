import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/data/listing_repository.dart';
import 'package:surplus_share/features/listing/data/remote_listing_repository.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_filter.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/listing_failure.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/domain/policy/listing_access_policy.dart';
import 'package:surplus_share/features/location/presentation/provider/location_provider.dart';

@immutable
class ListingState {
  const new({
    this.items = const <SurplusListing>[],
    this.isLoading = false,
    this.failure,
  });

  final List<SurplusListing> items;
  final bool isLoading;
  final ListingFailure? failure;

  ListingState copyWith({
    List<SurplusListing>? items,
    bool? isLoading,
    ListingFailure? failure,
    bool clearFailure = false,
  }) {
    return ListingState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ListingState &&
        listEquals(other.items, items) &&
        other.isLoading == isLoading &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(items), isLoading, failure);
}

final listingRepositoryProvider = Provider<ListingRepository>((ref) {
  final config = ref.watch(apiConfigProvider);
  if (config.isDemoMode) {
    final clock = ref.watch(clockProvider);
    return InMemoryListingRepository(clock: clock);
  }
  return RemoteListingRepository(dio: ref.watch(authenticatedDioProvider));
});

final listingChannelFilterProvider =
    NotifierProvider<ListingChannelFilterNotifier, ListingChannel?>(
      ListingChannelFilterNotifier.new,
    );

class ListingChannelFilterNotifier extends Notifier<ListingChannel?> {
  @override
  ListingChannel? build() {
    // Reset channel filter on logout / user switch so a consumer cannot stay
    // stuck on ListingChannel.donation after switching from a recipient.
    ref.watch(currentUserIdProvider);
    return null;
  }

  ListingChannel? get filter => state;

  set filter(ListingChannel? channel) {
    state = channel;
  }
}

final foodSafetyFilterProvider =
    NotifierProvider<FoodSafetyFilterNotifier, FoodSafetyFilter>(
      FoodSafetyFilterNotifier.new,
    );

class FoodSafetyFilterNotifier extends Notifier<FoodSafetyFilter> {
  @override
  FoodSafetyFilter build() {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const FoodSafetyFilter();
    final cached = ref
        .read(cacheStoreProvider)
        .readJson(CacheKeys.foodSafetyFilterFor(userId));
    if (cached == null) return const FoodSafetyFilter();
    return FoodSafetyFilter.fromJson(cached);
  }

  Future<void> setHalalOnly({required bool enabled}) async {
    await _update(
      state.copyWith(
        halalOnly: enabled,
        halalCertifiedOnly: enabled && state.halalCertifiedOnly,
      ),
    );
  }

  Future<void> setHalalCertifiedOnly({required bool enabled}) async {
    await _update(
      state.copyWith(
        halalCertifiedOnly: enabled,
        halalOnly: enabled || state.halalOnly,
      ),
    );
  }

  Future<void> toggleExcludedAllergen(FoodAllergen allergen) async {
    final next = Set<FoodAllergen>.of(state.excludedAllergens);
    if (!next.add(allergen)) {
      next.remove(allergen);
    }
    await _update(
      state.copyWith(excludedAllergens: Set<FoodAllergen>.unmodifiable(next)),
    );
  }

  Future<void> toggleCategory(FoodCategory category) async {
    final next = Set<FoodCategory>.of(state.categories);
    if (!next.add(category)) {
      next.remove(category);
    }
    await _update(
      state.copyWith(categories: Set<FoodCategory>.unmodifiable(next)),
    );
  }

  Future<void> reset() async {
    await _update(const FoodSafetyFilter());
  }

  Future<void> _update(FoodSafetyFilter next) async {
    state = next;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref
        .read(cacheStoreProvider)
        .writeJson(CacheKeys.foodSafetyFilterFor(userId), next.toJson());
  }
}

final listingNotifierProvider = NotifierProvider<ListingNotifier, ListingState>(
  ListingNotifier.new,
);

/// Automatically filters listings using [ListingAccessPolicy] and
/// [foodSafetyFilterProvider] so unverified accounts never receive
/// donation-only items and dietary/allergen filters apply everywhere.
final visibleListingsProvider = Provider<List<SurplusListing>>((ref) {
  final items = ref.watch(
    listingNotifierProvider.select((state) => state.items),
  );
  final permissions = ref.watch(currentPermissionProvider);
  final channelFilter = ref.watch(listingChannelFilterProvider);
  final safetyFilter = ref.watch(foodSafetyFilterProvider);

  return ListingAccessPolicy.filterVisible(
    items,
    permissions,
    channelFilter: channelFilter,
  ).where(safetyFilter.matches).toList(growable: false);
});

DateTime _watchCurrentTick(Ref ref) {
  final clock = ref.watch(clockProvider);
  final ticker = ref.watch(countdownTickerProvider);
  return ticker.isLoading ? clock() : (ticker.asData?.value ?? clock());
}

/// Returns only visible listings that are currently active and not expired.
///
/// Intentionally does NOT subscribe to [countdownTickerProvider] so list views
/// and maps do not rebuild every second; individual countdown badges reconcile
/// expired items via [listingCountdownProvider] -> `syncExpiredStatuses()`.
final Provider<List<SurplusListing>> activeVisibleListingsProvider =
    Provider.autoDispose<List<SurplusListing>>((ref) {
      final visible = ref.watch(visibleListingsProvider);
      final now = ref.watch(clockProvider)();

      return visible
          .where((item) => item.isAvailable(now: now))
          .toList(growable: false);
    });

/// Real-time countdown snapshot for a single listing driven by the single
/// shared [countdownTickerProvider]. Automatically reconciles expired status.
final ProviderFamily<PickupCountdownSnapshot?, String>
listingCountdownProvider = Provider.autoDispose
    .family<PickupCountdownSnapshot?, String>((ref, listingId) {
      final entry = ref.watch(
        listingNotifierProvider.select((state) {
          for (final item in state.items) {
            if (item.id == listingId) {
              return (window: item.pickupWindow, status: item.status);
            }
          }
          return null;
        }),
      );
      if (entry == null) return null;

      final now = _watchCurrentTick(ref);
      final snapshot = entry.window.snapshot(now: now);

      if (entry.status == ListingStatus.active && snapshot.isExpired) {
        final notifier = ref.read(listingNotifierProvider.notifier);
        unawaited(
          Future.microtask(() {
            if (ref.mounted) {
              notifier.syncExpiredStatuses();
            }
          }),
        );
      }

      return snapshot;
    });

class ListingNotifier extends Notifier<ListingState> {
  static const Duration _cacheTtl = Duration(minutes: 5);

  @override
  ListingState build() {
    ref.watch(currentUserIdProvider);
    final cached = ref
        .read(cacheStoreProvider)
        .readJson(CacheKeys.listingsSnapshot, allowStale: true);
    if (cached == null) return const ListingState();
    final rawItems = cached['items'];
    if (rawItems is! List) return const ListingState();
    try {
      final items = [
        for (final entry in rawItems.whereType<Map<dynamic, dynamic>>())
          SurplusListing.fromJson(Map<String, dynamic>.from(entry)),
      ];
      return ListingState(items: items);
    } on Object {
      return const ListingState();
    }
  }

  Future<void> loadListings() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref.read(listingRepositoryProvider).getListings();
    if (!ref.mounted) return;
    await result.fold<Future<void>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
      },
      (items) async {
        state = state.copyWith(isLoading: false, items: items);
        await _persistCache(items);
      },
    );
  }

  Future<void> _persistCache(List<SurplusListing> items) async {
    await ref.read(cacheStoreProvider).writeJson(CacheKeys.listingsSnapshot, {
      'items': [for (final item in items) item.toJson()],
    }, ttl: _cacheTtl);
  }

  /// Reconciles any active listings whose pickup window has elapsed into
  /// [ListingStatus.expired] without triggering unnecessary rebuilds.
  void syncExpiredStatuses() {
    final now = ref.read(clockProvider)().toUtc();
    var changed = false;
    final updated = [
      for (final item in state.items)
        if (item.status == ListingStatus.active &&
            item.pickupWindow.isExpired(now: now)) ...[
          (() {
            changed = true;
            return item.copyWith(status: ListingStatus.expired);
          })(),
        ] else
          item,
    ];

    if (changed) {
      state = state.copyWith(items: updated);
      unawaited(_persistCache(updated));
    }
  }

  Future<bool> createListing(CreateListingInput input) async {
    if (state.isLoading) return false;
    final permissions = ref.read(currentPermissionProvider);
    if (!ListingAccessPolicy.canCreate(permissions)) {
      state = state.copyWith(
        failure: const ListingPermissionDeniedFailure(
          'Hanya mitra terverifikasi yang dapat mengunggah stok makanan.',
        ),
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(listingRepositoryProvider)
        .createListing(input);
    if (!ref.mounted) return false;
    return await result.fold<Future<bool>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (created) async {
        final nextItems = [created, ...state.items];
        state = state.copyWith(isLoading: false, items: nextItems);
        await _persistCache(nextItems);
        if (!ref.mounted) return true;
        await ref
            .read(locationNotifierProvider.notifier)
            .notifyIfRelevant(created);
        return true;
      },
    );
  }

  Future<bool> convertToDonation(String listingId) {
    return _runManagedAction(
      listingId: listingId,
      deniedMessage:
          'Anda tidak memiliki izin mengalihkan listing ini ke Donasi Gratis.',
      action: () => ref
          .read(listingRepositoryProvider)
          .convertToDonation(listingId: listingId),
    );
  }

  Future<bool> closeListing(String listingId) {
    return _runManagedAction(
      listingId: listingId,
      deniedMessage: 'Anda tidak memiliki izin menutup listing ini.',
      action: () => ref
          .read(listingRepositoryProvider)
          .closeListing(listingId: listingId),
    );
  }

  Future<bool> claimStock({
    required String listingId,
    required int quantity,
  }) async {
    if (state.isLoading) return false;
    final target = _findById(listingId);
    if (target == null) {
      state = state.copyWith(failure: const ListingNotFoundFailure());
      return false;
    }

    final now = ref.read(clockProvider)().toUtc();
    final effectiveStatus = target.effectiveStatus(now: now);
    if (effectiveStatus == ListingStatus.expired) {
      syncExpiredStatuses();
      state = state.copyWith(failure: const ListingExpiredFailure());
      return false;
    }
    if (effectiveStatus != ListingStatus.active ||
        target.remainingQuantity <= 0) {
      state = state.copyWith(
        failure: const InsufficientStockFailure(
          'Listing sudah tidak tersedia.',
        ),
      );
      return false;
    }

    final permissions = ref.read(currentPermissionProvider);
    if (!ListingAccessPolicy.canClaim(target, permissions, now: now)) {
      final message = target.channel == ListingChannel.donation
          ? 'Donasi Gratis hanya dapat diklaim oleh panti asuhan atau '
                'komunitas terverifikasi.'
          : 'Anda tidak memiliki izin untuk mengklaim listing ini.';
      state = state.copyWith(failure: ListingPermissionDeniedFailure(message));
      return false;
    }

    String? quotaUserId;
    if (target.channel == ListingChannel.donation) {
      final claims = ref.read(currentClaimsProvider);
      if (claims != null && claims.role != AppRole.admin) {
        final userId = claims.subject;
        if (userId == null) {
          state = state.copyWith(
            failure: const ListingPermissionDeniedFailure(
              'Identitas penerima donasi tidak valid.',
            ),
          );
          return false;
        }

        final quotaResult = await ref
            .read(kycRepositoryProvider)
            .getDailyQuota(userId);
        if (!ref.mounted) return false;
        final quotaError = quotaResult.fold<ListingFailure?>(
          (failure) => ListingPermissionDeniedFailure(failure.message),
          (quota) => quota.canClaim(quantity)
              ? null
              : ListingQuotaExceededFailure(
                  remaining: quota.remaining,
                  dailyLimit: quota.dailyLimit,
                ),
        );
        if (quotaError != null) {
          state = state.copyWith(failure: quotaError);
          return false;
        }
        quotaUserId = userId;
      }
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref
        .read(listingRepositoryProvider)
        .claimStock(listingId: listingId, quantity: quantity);
    if (!ref.mounted) return false;
    return await result.fold<Future<bool>>(
      (failure) async {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (updated) async {
        ListingFailure? quotaSyncFailure;
        if (quotaUserId != null) {
          final consumed = await ref
              .read(kycRepositoryProvider)
              .consumeDailyQuota(userId: quotaUserId, quantity: quantity);
          if (!ref.mounted) return true;
          consumed.fold(
            (failure) => quotaSyncFailure = ListingPermissionDeniedFailure(
              failure.message,
            ),
            (quota) =>
                ref.read(kycNotifierProvider.notifier).syncDailyQuota(quota),
          );
        }
        final nextItems = _replaceItem(updated);
        state = state.copyWith(
          isLoading: false,
          items: nextItems,
          failure: quotaSyncFailure,
        );
        await _persistCache(nextItems);
        return quotaSyncFailure == null;
      },
    );
  }

  Future<bool> _runManagedAction({
    required String listingId,
    required String deniedMessage,
    required Future<Either<ListingFailure, SurplusListing>> Function() action,
  }) async {
    if (state.isLoading) return false;
    final target = _findById(listingId);
    if (target == null) {
      state = state.copyWith(failure: const ListingNotFoundFailure());
      return false;
    }

    if (!_canManage(target)) {
      state = state.copyWith(
        failure: ListingPermissionDeniedFailure(deniedMessage),
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await action();
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        state = state.copyWith(isLoading: false, failure: failure);
        return false;
      },
      (updated) {
        final nextItems = _replaceItem(updated);
        state = state.copyWith(isLoading: false, items: nextItems);
        unawaited(_persistCache(nextItems));
        return true;
      },
    );
  }

  bool _canManage(SurplusListing listing) {
    final claims = ref.read(currentClaimsProvider);
    if (claims == null) return false;
    final permissions = ref.read(currentPermissionProvider);

    return ListingAccessPolicy.canManage(
      listing,
      currentUserId: claims.subject,
      role: claims.role,
      permissions: permissions,
    );
  }

  SurplusListing? _findById(String id) {
    for (final item in state.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<SurplusListing> _replaceItem(SurplusListing updated) {
    return [
      for (final item in state.items)
        if (item.id == updated.id) updated else item,
    ];
  }
}
