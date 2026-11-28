import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/impact/presentation/provider/impact_provider.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/presentation/provider/location_provider.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';

class _MemStorage implements TokenStorage {
  AuthTokens? _t;
  @override
  Future<void> clearTokens() async => _t = null;
  @override
  Future<String?> getAccessToken() async => _t?.accessToken;
  @override
  Future<String?> getRefreshToken() async => _t?.refreshToken;
  @override
  Future<AuthTokens?> getTokens() async => _t;
  @override
  Future<void> saveTokens(AuthTokens tokens) async => _t = tokens;
}

void main() {
  test(
    'switching accounts isolates user-scoped notifiers and cache keys',
    () async {
      final now = DateTime.utc(2026, 11, 28, 10);
      final cache = InMemoryCacheStore(clock: () => now);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          cacheStoreProvider.overrideWithValue(cache),
          authRepositoryProvider.overrideWithValue(
            DummyAuthRepository(tokenStorage: _MemStorage()),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 1. Sign in as Donor Partner and populate partner-specific state.
      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.donorPartner.id);
      await container
          .read(locationNotifierProvider.notifier)
          .toggleFavoritePartner('partner-A');
      await container
          .read(locationNotifierProvider.notifier)
          .setNotificationRadius(3);
      container.read(listingChannelFilterProvider.notifier).filter =
          ListingChannel.donation;
      await container
          .read(foodSafetyFilterProvider.notifier)
          .setHalalOnly(enabled: true);
      await container
          .read(csrReportNotifierProvider.notifier)
          .exportPartnerCsrPdf(
            organizationName: 'Resto Nusantara',
            periodStart: now.subtract(const Duration(days: 7)),
            periodEnd: now,
          );

      expect(
        container.read(locationNotifierProvider).favoritePartnerIds,
        contains('partner-A'),
      );
      expect(container.read(csrReportNotifierProvider).lastPdfBytes, isNotNull);

      // 2. Logout and sign in as Consumer -> zero state leaked from Partner.
      await container.read(authNotifierProvider.notifier).logout();
      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);

      expect(
        container.read(locationNotifierProvider).favoritePartnerIds,
        isEmpty,
      );
      expect(container.read(locationNotifierProvider).radiusKm, 2.0);
      expect(container.read(listingChannelFilterProvider), isNull);
      expect(container.read(foodSafetyFilterProvider).halalOnly, isFalse);
      expect(container.read(csrReportNotifierProvider).lastPdfBytes, isNull);
      expect(container.read(kycNotifierProvider).dailyQuota, isNull);
      expect(container.read(reservationNotifierProvider).items, isEmpty);
    },
  );
}
