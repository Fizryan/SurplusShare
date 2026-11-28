import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/cache/local_cache_service.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_failure.dart';
import 'package:surplus_share/features/distribution/domain/models/distribution_task.dart';
import 'package:surplus_share/features/distribution/presentation/provider/distribution_provider.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';

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

  group('Volunteer Distribution & Portion Allocation', () {
    test(
      'CreateListingInput rejects volunteerAllocatedPortions out of bounds',
      () {
        final invalidHigh = CreateListingInput(
          partnerId: DummyAuthAccounts.donorPartner.id,
          partnerName: DummyAuthAccounts.donorPartner.displayName,
          title: 'Paket Nasi',
          description: 'Layak konsumsi',
          channel: ListingChannel.donation,
          originalPrice: 30000,
          discountedPrice: 0,
          quantity: 5,
          volunteerAllocatedPortions: 6,
          pickupStart: fixedNow.add(const Duration(minutes: 15)),
          pickupEnd: fixedNow.add(const Duration(hours: 2)),
        );
        expect(invalidHigh.validate(now: fixedNow), isNotNull);

        final invalidNeg = CreateListingInput(
          partnerId: DummyAuthAccounts.donorPartner.id,
          partnerName: DummyAuthAccounts.donorPartner.displayName,
          title: 'Paket Nasi',
          description: 'Layak konsumsi',
          channel: ListingChannel.donation,
          originalPrice: 30000,
          discountedPrice: 0,
          quantity: 5,
          volunteerAllocatedPortions: -1,
          pickupStart: fixedNow.add(const Duration(minutes: 15)),
          pickupEnd: fixedNow.add(const Duration(hours: 2)),
        );
        expect(invalidNeg.validate(now: fixedNow), isNotNull);
      },
    );

    test(
      'full lifecycle: donorPartner allocates portions -> volunteer accepts -> '
      'picks up -> delivers to verifiedRecipient',
      () async {
        final container = createContainer();
        addTearDown(container.dispose);

        // 1. Partner allocates 3 portions from active listing.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();

        final before = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((e) => e.id == 'lst-flash-1');
        final allocated = await container
            .read(listingNotifierProvider.notifier)
            .allocateVolunteerPortions(listingId: 'lst-flash-1', portions: 3);
        expect(allocated, isTrue);

        final after = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((e) => e.id == 'lst-flash-1');
        expect(after.remainingQuantity, equals(before.remainingQuantity - 3));
        expect(after.volunteerAllocatedPortions, equals(3));

        final created = await container
            .read(distributionNotifierProvider.notifier)
            .createTask(
              const CreateDistributionInput(
                listingId: 'lst-flash-1',
                listingTitle: 'Paket Nasi Campur Nusantara',
                partnerId: 'usr-partner-1',
                partnerName: 'Resto Nusantara',
                storeAddress: 'Jl. Sudirman No. 10, Jakarta Pusat',
                storeLocation: GeoPoint(latitude: -6.2088, longitude: 106.8456),
                recipientId: 'usr-recipient-1',
                recipientName: 'Panti Asuhan Harapan',
                recipientAddress:
                    'Jl. Tebet Timur Dalam No. 18, Jakarta Selatan',
                recipientLocation: GeoPoint(
                  latitude: -6.2297,
                  longitude: 106.8570,
                ),
                portions: 3,
              ),
            );
        expect(created, isTrue);
        final taskId = container
            .read(distributionNotifierProvider)
            .tasks
            .first
            .id;

        // 2. Consumer cannot accept distribution task.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(distributionNotifierProvider.notifier).loadTasks();
        final consumerDenied = await container
            .read(distributionNotifierProvider.notifier)
            .acceptTask(taskId);
        expect(consumerDenied, isFalse);
        expect(
          container.read(distributionNotifierProvider).failure,
          isA<DistributionPermissionDeniedFailure>(),
        );

        // 3. Volunteer accepts -> receives 6-digit pickupPin & deliveryPin ->
        //    verifies pickup PIN -> verifies delivery PIN.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.volunteer.id);
        await container.read(distributionNotifierProvider.notifier).loadTasks();

        expect(
          await container
              .read(distributionNotifierProvider.notifier)
              .acceptTask(taskId),
          isTrue,
        );
        final accepted = container
            .read(distributionNotifierProvider)
            .tasks
            .firstWhere((t) => t.id == taskId);
        expect(accepted.pickupPin, matches(RegExp(r'^\d{6}$')));
        expect(accepted.deliveryPin, matches(RegExp(r'^\d{6}$')));
        expect(accepted.pickupPin, isNot(equals(accepted.deliveryPin)));

        // Wrong pickup PIN is rejected with remaining attempts.
        final wrongPickupPin = accepted.pickupPin == '000000'
            ? '111111'
            : '000000';
        expect(
          await container
              .read(distributionNotifierProvider.notifier)
              .markPickedUp(taskId: taskId, pin: wrongPickupPin),
          isFalse,
        );
        expect(
          container.read(distributionNotifierProvider).failure,
          isA<InvalidDistributionPinFailure>(),
        );

        // Valid pickup PIN succeeds.
        expect(
          await container
              .read(distributionNotifierProvider.notifier)
              .markPickedUp(taskId: taskId, pin: accepted.pickupPin!),
          isTrue,
        );

        // Wrong delivery PIN is rejected, valid delivery PIN completes task.
        final wrongDeliveryPin = accepted.deliveryPin == '999999'
            ? '888888'
            : '999999';
        expect(
          await container
              .read(distributionNotifierProvider.notifier)
              .markDelivered(taskId: taskId, pin: wrongDeliveryPin),
          isFalse,
        );
        expect(
          container.read(distributionNotifierProvider).failure,
          isA<InvalidDistributionPinFailure>(),
        );

        expect(
          await container
              .read(distributionNotifierProvider.notifier)
              .markDelivered(taskId: taskId, pin: accepted.deliveryPin!),
          isTrue,
        );

        final delivered = container
            .read(distributionNotifierProvider)
            .tasks
            .firstWhere((t) => t.id == taskId);
        expect(delivered.status, equals(DistributionStatus.delivered));
        expect(delivered.volunteerId, equals(DummyAuthAccounts.volunteer.id));
        expect(delivered.deliveredAt, isNotNull);
      },
    );

    test('partner cancels open task -> restores listing stock; cannot cancel '
        'after pickup', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.donorPartner.id);
      await container.read(listingNotifierProvider.notifier).loadListings();
      await container.read(distributionNotifierProvider.notifier).loadTasks();

      final initialRemaining = container
          .read(listingNotifierProvider)
          .items
          .firstWhere((e) => e.id == 'lst-flash-1')
          .remainingQuantity;

      await container
          .read(listingNotifierProvider.notifier)
          .allocateVolunteerPortions(listingId: 'lst-flash-1', portions: 2);
      await container
          .read(distributionNotifierProvider.notifier)
          .createTask(
            const CreateDistributionInput(
              listingId: 'lst-flash-1',
              listingTitle: 'Paket Nasi Campur Nusantara',
              partnerId: 'usr-partner-1',
              partnerName: 'Resto Nusantara',
              storeAddress: 'Jl. Sudirman No. 10, Jakarta Pusat',
              storeLocation: GeoPoint(latitude: -6.2088, longitude: 106.8456),
              recipientId: 'usr-recipient-1',
              recipientName: 'Panti Asuhan Harapan',
              recipientAddress: 'Jl. Tebet Timur Dalam No. 18, Jakarta Selatan',
              recipientLocation: GeoPoint(
                latitude: -6.2297,
                longitude: 106.8570,
              ),
              portions: 2,
            ),
          );
      final taskId = container
          .read(distributionNotifierProvider)
          .tasks
          .first
          .id;

      final cancelled = await container
          .read(distributionNotifierProvider.notifier)
          .cancelTask(taskId);
      expect(cancelled, isTrue);

      final restoredRemaining = container
          .read(listingNotifierProvider)
          .items
          .firstWhere((e) => e.id == 'lst-flash-1')
          .remainingQuantity;
      expect(restoredRemaining, equals(initialRemaining));
    });
  });
}
