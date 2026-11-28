import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/core/utils/constants/box_strings.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/data/location_service.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/location_failure.dart';
import 'package:surplus_share/features/location/domain/models/radius_notification_event.dart';
import 'package:surplus_share/features/location/presentation/provider/location_provider.dart';

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

class _StubLocationService implements LocationService {
  new(this._point);

  final GeoPoint _point;

  @override
  Future<Either<LocationFailure, GeoPoint>> getCurrentLocation() async {
    return right(_point);
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

void main() {
  group('GeoPoint Haversine & LatLng', () {
    test('computes accurate distance and converts to latlong2 LatLng', () {
      // ~1.11 km apart (0.01 deg latitude)
      const a = GeoPoint(latitude: -6.2000, longitude: 106.8456);
      const b = GeoPoint(latitude: -6.2100, longitude: 106.8456);

      final km = a.distanceInKmTo(b);
      expect(km, closeTo(1.11, 0.05));
      expect(a.isValid, isTrue);
      expect(a.toLatLng().latitude, -6.2000);
    });
  });

  group('LocationNotifier caching, nearby & real-time notifications', () {
    test(
      'hydrates cached location/favorites/radius immediately and sorts nearby '
      'listings nearest-first',
      () async {
        final now = DateTime.utc(2026, 11, 27, 18);
        final cache = InMemoryCacheStore(clock: () => now);
        // Pre-seed cache with Jakarta Pusat location near seeded listings.
        await cache.writeJson(
          CacheKeys.lastLocation,
          const GeoPoint(latitude: -6.2088, longitude: 106.8456).toJson(),
          ttl: const Duration(minutes: 30),
        );
        await cache.writeJson(
          CacheKeys.notificationRadiusFor(DummyAuthAccounts.consumer.id),
          {'radius_km': 1.0},
        );

        final tokenStorage = _InMemoryTokenStorage();
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            cacheStoreProvider.overrideWithValue(cache),
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(
              DummyAuthRepository(tokenStorage: tokenStorage),
            ),
            locationServiceProvider.overrideWithValue(
              _StubLocationService(
                const GeoPoint(latitude: -6.2090, longitude: 106.8456),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);

        // Instant hydration before GPS call!
        final initialLoc = container.read(locationNotifierProvider);
        expect(initialLoc.currentLocation?.latitude, -6.2088);
        expect(initialLoc.radiusKm, 1.0);

        // Clamp radius outside 1-3 km range.
        await container
            .read(locationNotifierProvider.notifier)
            .setNotificationRadius(10);
        expect(container.read(locationNotifierProvider).radiusKm, 3.0);

        // Consumer sees only discount nearby listings sorted nearest-first.
        await container.read(listingNotifierProvider.notifier).loadListings();

        final nearby = container.read(nearbyListingsProvider);
        expect(nearby.length, 2);
        expect(nearby.first.listing.id, 'lst-flash-1');
        expect(nearby.first.formattedDistance, '0 m');
        expect(nearby[1].listing.id, 'lst-bag-1');
        expect(
          nearby.every((n) => n.listing.channel == ListingChannel.discount),
          isTrue,
        );
      },
    );

    test(
      'triggers real-time push notifications for withinRadius, favoritePartner,'
      ' both, and blocks Donation alerts for unverified consumer',
      () async {
        final now = DateTime.utc(2026, 11, 27, 18);
        final cache = InMemoryCacheStore(clock: () => now);
        final tokenStorage = _InMemoryTokenStorage();
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            cacheStoreProvider.overrideWithValue(cache),
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(
              DummyAuthRepository(tokenStorage: tokenStorage),
            ),
            locationServiceProvider.overrideWithValue(
              _StubLocationService(
                const GeoPoint(latitude: -6.2088, longitude: 106.8456),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(locationNotifierProvider.notifier)
            .refreshLocation();
        await container
            .read(locationNotifierProvider.notifier)
            .setNotificationRadius(2);

        // Partner creates nearby Flash Sale (~0.5 km) -> triggers withinRadius.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );

        final start = now.add(const Duration(hours: 1));
        final end = now.add(const Duration(hours: 3));

        await container
            .read(listingNotifierProvider.notifier)
            .createListing(
              CreateListingInput(
                partnerId: DummyAuthAccounts.donorPartner.id,
                partnerName: DummyAuthAccounts.donorPartner.displayName,
                title: 'Nasi Goreng Surplus',
                description: 'Baru diunggah!',
                channel: ListingChannel.discount,
                discountFormat: DiscountFormat.flashSale,
                originalPrice: 40000,
                discountedPrice: 20000,
                quantity: 5,
                pickupStart: start,
                pickupEnd: end,
                location: const GeoPoint(
                  latitude: -6.2130,
                  longitude: 106.8456,
                ),
              ),
            );

        final dispatcher = container.read(pushNotificationDispatcherProvider);
        expect(dispatcher.history.length, 1);
        expect(
          dispatcher.history.first.reason,
          NotificationTriggerReason.withinRadius,
        );

        // Mark partner as favorite and create listing 10 km away ->
        // still notifies with favoritePartner!
        await container
            .read(locationNotifierProvider.notifier)
            .toggleFavoritePartner(DummyAuthAccounts.donorPartner.id);
        await container
            .read(listingNotifierProvider.notifier)
            .createListing(
              CreateListingInput(
                partnerId: DummyAuthAccounts.donorPartner.id,
                partnerName: DummyAuthAccounts.donorPartner.displayName,
                title: 'Roti Favorit Cabang Jauh',
                description: 'Di luar radius 2km tapi favorit.',
                channel: ListingChannel.discount,
                discountFormat: DiscountFormat.surpriseBag,
                originalPrice: 50000,
                discountedPrice: 25000,
                quantity: 3,
                pickupStart: start,
                pickupEnd: end,
                location: const GeoPoint(
                  latitude: -6.3000,
                  longitude: 106.8456,
                ),
              ),
            );
        expect(dispatcher.history.length, 2);
        expect(
          dispatcher.history.first.reason,
          NotificationTriggerReason.favoritePartner,
        );

        // Switch to unverified consumer -> Donation listing within 0.5 km must
        // NOT trigger a notification!
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(listingNotifierProvider.notifier).loadListings();
        final donation = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-donation-1');

        final blockedEvent = await container
            .read(locationNotifierProvider.notifier)
            .notifyIfRelevant(donation);
        expect(blockedEvent, isNull);

        // Switch to verifiedRecipient -> same Donation listing DOES notify!
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
            );
        await container
            .read(locationNotifierProvider.notifier)
            .toggleFavoritePartner(DummyAuthAccounts.donorPartner.id);
        final allowedEvent = await container
            .read(locationNotifierProvider.notifier)
            .notifyIfRelevant(donation);
        expect(allowedEvent, isNotNull);
        expect(allowedEvent!.reason, NotificationTriggerReason.both);
      },
    );

    test('GeolocatorLocationService falls back to Android LocationManager and '
        'getLastKnownPosition on timeout', () async {
      const expectedPoint = GeoPoint(latitude: -6.2088, longitude: 106.8456);

      // Tier 1 timeout -> Tier 2 Android LocationManager succeeds.
      final tier2Service = GeolocatorLocationService(
        isAndroidOverride: true,
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition:
            ({
              required accuracy,
              required timeLimit,
              required forceAndroidLocationManager,
            }) async {
              if (!forceAndroidLocationManager) {
                throw TimeoutException('fused timeout');
              }
              return expectedPoint;
            },
      );
      final tier2Res = await tier2Service.getCurrentLocation();
      expect(tier2Res, right<LocationFailure, GeoPoint>(expectedPoint));

      // Tier 1 & Tier 2 timeout -> Tier 3 getLastKnownPosition succeeds.
      final tier3Service = GeolocatorLocationService(
        isAndroidOverride: true,
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition: ({
          required accuracy,
          required timeLimit,
          required forceAndroidLocationManager,
        }) async => throw TimeoutException('active timeout'),
        fetchLastKnown: ({required forceAndroidLocationManager}) async =>
            forceAndroidLocationManager ? expectedPoint : null,
      );
      final tier3Res = await tier3Service.getCurrentLocation();
      expect(tier3Res, right<LocationFailure, GeoPoint>(expectedPoint));
    });

    test('GeolocatorLocationService falls back to Android LocationManager and '
        'getLastKnownPosition on timeout', () async {
      const expectedPoint = GeoPoint(latitude: -6.2088, longitude: 106.8456);

      // Tier 1 timeout -> Tier 2 Android LocationManager succeeds.
      final tier2Service = GeolocatorLocationService(
        isAndroidOverride: true,
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition:
            ({
              required accuracy,
              required timeLimit,
              required forceAndroidLocationManager,
            }) async {
              if (!forceAndroidLocationManager) {
                throw TimeoutException('fused timeout');
              }
              return expectedPoint;
            },
      );
      final tier2Res = await tier2Service.getCurrentLocation();
      expect(tier2Res, right<LocationFailure, GeoPoint>(expectedPoint));

      // Tier 1 & Tier 2 timeout -> Tier 3 getLastKnownPosition succeeds.
      final tier3Service = GeolocatorLocationService(
        isAndroidOverride: true,
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        fetchPosition: ({
          required accuracy,
          required timeLimit,
          required forceAndroidLocationManager,
        }) async => throw TimeoutException('active timeout'),
        fetchLastKnown: ({required forceAndroidLocationManager}) async =>
            forceAndroidLocationManager ? expectedPoint : null,
      );
      final tier3Res = await tier3Service.getCurrentLocation();
      expect(tier3Res, right<LocationFailure, GeoPoint>(expectedPoint));
    });
  });
}
