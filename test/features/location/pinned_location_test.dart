import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';
import 'package:surplus_share/features/location/domain/models/pinned_location.dart';
import 'package:surplus_share/features/location/presentation/provider/pinned_location_provider.dart';

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
  final fixedNow = DateTime.utc(2026, 11, 28, 12);

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => fixedNow),
        tokenStorageProvider.overrideWithValue(_InMemoryTokenStorage()),
        cacheStoreProvider.overrideWithValue(
          InMemoryCacheStore(clock: () => fixedNow),
        ),
      ],
    );
  }

  group('PinnedLocation (Fixed Store & Verified Recipient Map Pin)', () {
    test(
      'donorPartner saves fixed store pin and isolates cache per user',
      () async {
        final container = createContainer();
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        final notifier = container.read(
          pinnedLocationNotifierProvider.notifier,
        );
        await notifier.loadMyLocation();

        expect(
          container.read(pinnedLocationNotifierProvider).myLocation?.placeName,
          equals('Resto Nusantara'),
        );

        const updatedPoint = GeoPoint(latitude: -6.1950, longitude: 106.8230);
        final saved = await notifier.saveMyLocation(
          placeName: 'Resto Nusantara Cabang Menteng',
          address: 'Jl. Menteng Raya No. 45, Jakarta Pusat',
          point: updatedPoint,
        );
        expect(saved, isTrue);

        final current = container
            .read(pinnedLocationNotifierProvider)
            .myLocation;
        expect(current?.point, equals(updatedPoint));
        expect(
          current?.address,
          equals('Jl. Menteng Raya No. 45, Jakarta Pusat'),
        );

        // Switching to verifiedRecipient must NOT leak donorPartner's pin.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
            );
        await container
            .read(pinnedLocationNotifierProvider.notifier)
            .loadMyLocation();
        final recipientPin = container
            .read(pinnedLocationNotifierProvider)
            .myLocation;
        expect(
          recipientPin?.ownerId,
          equals(DummyAuthAccounts.verifiedRecipient.id),
        );
        expect(recipientPin?.placeName, equals('Panti Asuhan Harapan'));
      },
    );

    test(
      'verifiedRecipient updates fixed drop-off pin and appears in recipient '
      'directory',
      () async {
        final container = createContainer();
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
            );
        final notifier = container.read(
          pinnedLocationNotifierProvider.notifier,
        );

        const newDropoff = GeoPoint(latitude: -6.2410, longitude: 106.8615);
        final ok = await notifier.saveMyLocation(
          placeName: 'Panti Asuhan Harapan Baru',
          address: 'Jl. Otista Raya No. 88, Jakarta Timur',
          point: newDropoff,
        );
        expect(ok, isTrue);

        final recipients = container
            .read(pinnedLocationNotifierProvider)
            .verifiedRecipients;
        expect(recipients, isNotEmpty);
        expect(recipients.first.point, equals(newDropoff));
        expect(
          recipients.first.address,
          equals('Jl. Otista Raya No. 88, Jakarta Timur'),
        );
      },
    );

    test('rejects short address or invalid coordinates', () {
      final invalid = PinnedLocation(
        ownerId: 'usr-partner-1',
        ownerRole: DummyAuthAccounts.donorPartner.role,
        placeName: 'OK Store',
        address: 'Pendek',
        point: const GeoPoint(latitude: -6.2, longitude: 106.8),
        updatedAt: fixedNow,
      );
      expect(invalid.validate(), isNotNull);

      final invalidCoord = invalid.copyWith(
        address: 'Jl. Sudirman No. 10, Jakarta Pusat',
        point: const GeoPoint(latitude: 120, longitude: 106.8),
      );
      expect(invalidCoord.validate(), isNotNull);
    });
  });
}
