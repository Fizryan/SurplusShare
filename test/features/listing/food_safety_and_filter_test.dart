import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_filter.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
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

void main() {
  group('FoodSafetyDeclaration validation', () {
    final now = DateTime.utc(2026, 11, 27, 18);
    final window = PickupWindow(
      start: DateTime.utc(2026, 11, 27, 20),
      end: DateTime.utc(2026, 11, 27, 22),
    );

    test(
      'accepts valid declaration and rejects hygiene/safeUntil violations',
      () {
        final valid = FoodSafetyDeclaration(
          halalStatus: HalalStatus.halalCertified,
          category: FoodCategory.readyToEat,
          allergens: const {FoodAllergen.peanuts},
          safeUntil: DateTime.utc(2026, 11, 28, 2),
          hygieneConfirmed: true,
        );
        final unconfirmed = FoodSafetyDeclaration(
          halalStatus: HalalStatus.halalFriendly,
          category: FoodCategory.bakery,
          safeUntil: DateTime.utc(2026, 11, 28, 2),
          hygieneConfirmed: false,
        );
        final beforePickupEnd = FoodSafetyDeclaration(
          halalStatus: HalalStatus.halalFriendly,
          category: FoodCategory.bakery,
          safeUntil: DateTime.utc(2026, 11, 27, 21),
          hygieneConfirmed: true,
        );
        final beyond72h = FoodSafetyDeclaration(
          halalStatus: HalalStatus.halalFriendly,
          category: FoodCategory.rawIngredients,
          safeUntil: DateTime.utc(2026, 12, 1, 23),
          hygieneConfirmed: true,
        );

        expect(valid.validate(pickupWindow: window, now: now), isNull);
        expect(unconfirmed.validate(pickupWindow: window, now: now), isNotNull);
        expect(
          beforePickupEnd.validate(pickupWindow: window, now: now),
          isNotNull,
        );
        expect(beyond72h.validate(pickupWindow: window, now: now), isNotNull);
      },
    );

    test('CreateListingInput rejects invalid GeoPoint coordinates', () {
      final input = CreateListingInput(
        partnerId: 'p1',
        partnerName: 'Resto',
        title: 'Test',
        description: 'Desc',
        channel: ListingChannel.discount,
        discountFormat: DiscountFormat.flashSale,
        originalPrice: 50000,
        discountedPrice: 25000,
        quantity: 2,
        pickupStart: window.start,
        pickupEnd: window.end,
        location: const GeoPoint(latitude: 999, longitude: 106),
      );

      expect(input.validate(now: now), isNotNull);
    });
  });

  group('FoodSafetyFilter fail-safe, persistence & notification blocking', () {
    test('fail-safe hides undeclared listings when any filter is active', () {
      final now = DateTime.utc(2026, 11, 27, 18);
      final undeclared = SurplusListing(
        id: 'u1',
        partnerId: 'p1',
        partnerName: 'Resto',
        title: 'Tanpa Deklarasi',
        description: 'Desc',
        channel: ListingChannel.discount,
        discountFormat: DiscountFormat.flashSale,
        originalPrice: 50000,
        discountedPrice: 25000,
        totalQuantity: 5,
        remainingQuantity: 5,
        pickupWindow: PickupWindow(
          start: now.add(const Duration(hours: 1)),
          end: now.add(const Duration(hours: 3)),
        ),
        status: ListingStatus.active,
        createdAt: now,
      );

      expect(const FoodSafetyFilter().matches(undeclared), isTrue);
      expect(
        const FoodSafetyFilter(halalOnly: true).matches(undeclared),
        isFalse,
      );
      expect(
        const FoodSafetyFilter(excludedAllergens: {FoodAllergen.peanuts})
            .matches(undeclared),
        isFalse,
      );
    });

    test('filters visibleListings, persists in CacheStore, and blocks unsafe '
        'real-time notifications', () async {
      final now = DateTime.utc(2026, 11, 27, 18);
      final cache = InMemoryCacheStore(clock: () => now);
      final tokenStorage = _InMemoryTokenStorage();

      ProviderContainer makeContainer() {
        return ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            cacheStoreProvider.overrideWithValue(cache),
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(
              DummyAuthRepository(tokenStorage: tokenStorage),
            ),
          ],
        );
      }

      final container = makeContainer();
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.donorPartner.id);
      await container.read(listingNotifierProvider.notifier).loadListings();

      // Seeded listings owned by donorPartner (2 discount + 1 donation):
      // - lst-flash-1: halalCertified, readyToEat, allergens: {peanuts}
      // - lst-bag-1: halalFriendly, bakery, allergens: {gluten, dairy}
      // - lst-donation-1: halalCertified, readyToEat, allergens: {}
      expect(container.read(visibleListingsProvider).length, 3);

      // Exclude peanuts -> hides lst-flash-1.
      await container
          .read(foodSafetyFilterProvider.notifier)
          .toggleExcludedAllergen(FoodAllergen.peanuts);
      expect(
        container.read(visibleListingsProvider).map((e) => e.id),
        equals(['lst-bag-1', 'lst-donation-1']),
      );

      // Enable halalCertifiedOnly -> hides halalFriendly lst-bag-1 too.
      await container
          .read(foodSafetyFilterProvider.notifier)
          .setHalalCertifiedOnly(enabled: true);
      expect(
        container.read(visibleListingsProvider).map((e) => e.id),
        equals(['lst-donation-1']),
      );

      // New container hydrates the user-scoped filter from CacheStore.
      final rehydrated = makeContainer();
      addTearDown(rehydrated.dispose);
      await rehydrated
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.donorPartner.id);
      final savedFilter = rehydrated.read(foodSafetyFilterProvider);
      expect(savedFilter.halalCertifiedOnly, isTrue);
      expect(savedFilter.excludedAllergens, equals({FoodAllergen.peanuts}));

      // Creating a Non-Halal listing nearby does NOT trigger push
      // notification because halalCertifiedOnly is active!
      await container
          .read(locationNotifierProvider.notifier)
          .toggleFavoritePartner(DummyAuthAccounts.donorPartner.id);
      await container
          .read(listingNotifierProvider.notifier)
          .createListing(
            CreateListingInput(
              partnerId: DummyAuthAccounts.donorPartner.id,
              partnerName: DummyAuthAccounts.donorPartner.displayName,
              title: 'Pork Ramen Surplus',
              description: 'Non-Halal',
              channel: ListingChannel.discount,
              discountFormat: DiscountFormat.flashSale,
              originalPrice: 60000,
              discountedPrice: 30000,
              quantity: 3,
              pickupStart: now.add(const Duration(hours: 1)),
              pickupEnd: now.add(const Duration(hours: 3)),
              foodSafety: FoodSafetyDeclaration(
                halalStatus: HalalStatus.nonHalal,
                category: FoodCategory.readyToEat,
                safeUntil: now.add(const Duration(hours: 6)),
                hygieneConfirmed: true,
              ),
            ),
          );

      expect(
        container.read(pushNotificationDispatcherProvider).history,
        isEmpty,
      );
    });
  });
}
