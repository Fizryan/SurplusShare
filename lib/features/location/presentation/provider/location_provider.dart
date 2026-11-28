import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/data/location_service.dart';
import 'package:surplus_share/features/location/data/push_notification_dispatcher.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/location_failure.dart';
import 'package:surplus_share/features/location/domain/models/nearby_listing.dart';
import 'package:surplus_share/features/location/domain/models/radius_notification_event.dart';
import 'package:surplus_share/features/location/domain/policy/radius_notification_policy.dart';

@immutable
class LocationState {
  const new({
    this.currentLocation,
    this.radiusKm = RadiusNotificationPolicy.defaultRadiusKm,
    this.favoritePartnerIds = const <String>{},
    this.recentNotifications = const <RadiusNotificationEvent>[],
    this.isLocating = false,
    this.failure,
  });

  final GeoPoint? currentLocation;
  final double radiusKm;
  final Set<String> favoritePartnerIds;
  final List<RadiusNotificationEvent> recentNotifications;
  final bool isLocating;
  final LocationFailure? failure;

  LocationState copyWith({
    GeoPoint? currentLocation,
    double? radiusKm,
    Set<String>? favoritePartnerIds,
    List<RadiusNotificationEvent>? recentNotifications,
    bool? isLocating,
    LocationFailure? failure,
    bool clearFailure = false,
  }) {
    return LocationState(
      currentLocation: currentLocation ?? this.currentLocation,
      radiusKm: radiusKm ?? this.radiusKm,
      favoritePartnerIds: favoritePartnerIds ?? this.favoritePartnerIds,
      recentNotifications: recentNotifications ?? this.recentNotifications,
      isLocating: isLocating ?? this.isLocating,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationState &&
        other.currentLocation == currentLocation &&
        other.radiusKm == radiusKm &&
        setEquals(other.favoritePartnerIds, favoritePartnerIds) &&
        listEquals(other.recentNotifications, recentNotifications) &&
        other.isLocating == isLocating &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(
    currentLocation,
    radiusKm,
    Object.hashAllUnordered(favoritePartnerIds),
    Object.hashAll(recentNotifications),
    isLocating,
    failure,
  );
}

final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});

final pushNotificationDispatcherProvider = Provider<PushNotificationDispatcher>(
  (ref) {
    final dispatcher = InMemoryPushNotificationDispatcher();
    ref.onDispose(dispatcher.dispose);
    return dispatcher;
  },
);

final locationNotifierProvider =
    NotifierProvider<LocationNotifier, LocationState>(LocationNotifier.new);

/// Nearest-first available listings within the user's configured 1–3 km radius,
/// strictly filtered by RBAC/KYC visibility.
///
/// Uses narrow `.select(...)` watches so `isLocating`, `failure`,
/// notifications, and 1-second ticks never recompute Haversine or rebuild map.
final Provider<List<NearbyListing>> nearbyListingsProvider =
    Provider.autoDispose<List<NearbyListing>>((ref) {
      final userLocation = ref.watch(
        locationNotifierProvider.select((s) => s.currentLocation),
      );
      if (userLocation == null) return const <NearbyListing>[];

      final radiusKm = ref.watch(
        locationNotifierProvider.select((s) => s.radiusKm),
      );
      final favoritePartnerIds = ref.watch(
        locationNotifierProvider.select((s) => s.favoritePartnerIds),
      );
      final listings = ref.watch(activeVisibleListingsProvider);
      final permissions = ref.watch(currentPermissionProvider);
      final now = ref.read(clockProvider)();

      return RadiusNotificationPolicy.findNearby(
        listings: listings,
        userLocation: userLocation,
        radiusKm: radiusKm,
        favoritePartnerIds: favoritePartnerIds,
        permissions: permissions,
        now: now,
      );
    });

class LocationNotifier extends Notifier<LocationState> {
  static const Duration _locationCacheTtl = Duration(minutes: 30);

  @override
  LocationState build() {
    // User-scoped hydration prevents favorite partners, radius, and donation
    // notifications from leaking across accounts.
    final userId = ref.watch(currentUserIdProvider);
    final cache = ref.read(cacheStoreProvider);
    return LocationState(
      currentLocation: _readCachedLocation(cache),
      radiusKm: _readCachedRadius(cache, userId),
      favoritePartnerIds: _readCachedFavorites(cache, userId),
    );
  }

  /// Refreshes GPS position and persists it to [CacheStore] for instant load
  /// on subsequent app launches.
  Future<bool> refreshLocation() async {
    if (state.isLocating) return false;
    state = state.copyWith(isLocating: true, clearFailure: true);
    final result = await ref.read(locationServiceProvider).getCurrentLocation();
    if (!ref.mounted) return false;
    return await result.fold<Future<bool>>(
      (failure) async {
        state = state.copyWith(isLocating: false, failure: failure);
        return false;
      },
      (point) async {
        await ref
            .read(cacheStoreProvider)
            .writeJson(
              CacheKeys.lastLocation,
              point.toJson(),
              ttl: _locationCacheTtl,
            );
        if (!ref.mounted) return true;
        state = state.copyWith(isLocating: false, currentLocation: point);
        return true;
      },
    );
  }

  /// Sets a user-selected manual area coordinate (fallback when GPS times out
  /// indoors or on emulators) and persists it to [CacheStore].
  Future<bool> setManualLocation(GeoPoint point) async {
    if (!point.isValid) return false;
    await ref
        .read(cacheStoreProvider)
        .writeJson(
          CacheKeys.lastLocation,
          point.toJson(),
          ttl: _locationCacheTtl,
        );
    if (!ref.mounted) return true;
    state = state.copyWith(
      isLocating: false,
      currentLocation: point,
      clearFailure: true,
    );
    return true;
  }

  Future<bool> openLocationSettings() {
    return ref.read(locationServiceProvider).openLocationSettings();
  }

  Future<bool> openAppSettings() {
    return ref.read(locationServiceProvider).openAppSettings();
  }

  /// Updates user notification radius (clamped to 1–3 km) and persists it.
  Future<void> setNotificationRadius(double radiusKm) async {
    final clamped = RadiusNotificationPolicy.clampRadiusKm(radiusKm);
    state = state.copyWith(radiusKm: clamped);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref.read(cacheStoreProvider).writeJson(
      CacheKeys.notificationRadiusFor(userId),
      {'radius_km': clamped},
    );
  }

  /// Toggles a partner as favorite and persists the updated set to cache.
  Future<void> toggleFavoritePartner(String partnerId) async {
    final next = Set<String>.of(state.favoritePartnerIds);
    if (!next.add(partnerId)) {
      next.remove(partnerId);
    }
    final immutable = Set<String>.unmodifiable(next);
    state = state.copyWith(favoritePartnerIds: immutable);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref.read(cacheStoreProvider).writeJson(
      CacheKeys.favoritePartnersFor(userId),
      {'partner_ids': immutable.toList(growable: false)},
    );
  }

  /// Evaluates a newly published surplus listing and dispatches a real-time
  /// push notification if it matches a favorite partner or 1–3 km radius,
  /// respecting the user's Halal & allergen safety filter.
  Future<RadiusNotificationEvent?> notifyIfRelevant(
    SurplusListing listing,
  ) async {
    final safetyFilter = ref.read(foodSafetyFilterProvider);
    if (!safetyFilter.matches(listing)) return null;

    final permissions = ref.read(currentPermissionProvider);
    final now = ref.read(clockProvider)();

    final event = RadiusNotificationPolicy.evaluateNewListingNotification(
      listing: listing,
      userLocation: state.currentLocation,
      radiusKm: state.radiusKm,
      favoritePartnerIds: state.favoritePartnerIds,
      permissions: permissions,
      now: now,
    );
    if (event == null) return null;

    await ref.read(pushNotificationDispatcherProvider).dispatch(event);
    if (!ref.mounted) return event;
    state = state.copyWith(
      recentNotifications: [event, ...state.recentNotifications],
    );
    return event;
  }

  GeoPoint? _readCachedLocation(CacheStore cache) {
    final map = cache.readJson(CacheKeys.lastLocation, allowStale: true);
    if (map == null) return null;
    try {
      final point = GeoPoint.fromJson(map);
      return point.isValid ? point : null;
    } on FormatException {
      return null;
    }
  }

  double _readCachedRadius(CacheStore cache, String? userId) {
    if (userId == null) return RadiusNotificationPolicy.defaultRadiusKm;
    final map = cache.readJson(CacheKeys.notificationRadiusFor(userId));
    final raw = map?['radius_km'];
    if (raw is num) {
      return RadiusNotificationPolicy.clampRadiusKm(raw.toDouble());
    }
    return RadiusNotificationPolicy.defaultRadiusKm;
  }

  Set<String> _readCachedFavorites(CacheStore cache, String? userId) {
    if (userId == null) return const <String>{};
    final map = cache.readJson(CacheKeys.favoritePartnersFor(userId));
    final raw = map?['partner_ids'];
    if (raw is List) {
      return Set<String>.unmodifiable(raw.whereType<String>());
    }
    return const <String>{};
  }
}
