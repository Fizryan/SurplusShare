import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/kyc/data/kyc_repository.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/data/listing_repository.dart';
import 'package:surplus_share/features/listing/domain/models/create_listing_input.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/domain/models/listing_failure.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';

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

ProviderContainer _createContainer() {
  final tokenStorage = _InMemoryTokenStorage();
  return ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(tokenStorage),
      authRepositoryProvider.overrideWithValue(
        DummyAuthRepository(tokenStorage: tokenStorage),
      ),
      listingRepositoryProvider.overrideWithValue(InMemoryListingRepository()),
    ],
  );
}

void main() {
  group('CreateListingInput validation', () {
    final start = DateTime.now().toUtc().add(const Duration(hours: 1));
    final end = start.add(const Duration(hours: 3));

    test('accepts flexible discount range between 10% and 90%', () {
      for (final discountedPrice in [90000, 40000, 10000]) {
        final input = CreateListingInput(
          partnerId: 'p1',
          partnerName: 'Resto A',
          title: 'Paket Sore',
          description: 'Makanan segar',
          channel: ListingChannel.discount,
          discountFormat: DiscountFormat.flashSale,
          originalPrice: 100000,
          discountedPrice: discountedPrice,
          quantity: 5,
          pickupStart: start,
          pickupEnd: end,
        );
        expect(input.validate(), isNull);
      }
    });

    test('rejects discount below 10% or above 90%', () {
      final tooSmall = CreateListingInput(
        partnerId: 'p1',
        partnerName: 'Resto A',
        title: 'Paket Sore',
        description: 'Makanan segar',
        channel: ListingChannel.discount,
        discountFormat: DiscountFormat.flashSale,
        originalPrice: 100000,
        discountedPrice: 95000,
        quantity: 5,
        pickupStart: start,
        pickupEnd: end,
      );
      final tooLarge = CreateListingInput(
        partnerId: 'p1',
        partnerName: 'Resto A',
        title: 'Paket Sore',
        description: 'Makanan segar',
        channel: ListingChannel.discount,
        discountFormat: DiscountFormat.surpriseBag,
        originalPrice: 100000,
        discountedPrice: 5000,
        quantity: 5,
        pickupStart: start,
        pickupEnd: end,
      );

      expect(tooSmall.validate(), isNotNull);
      expect(tooLarge.validate(), isNotNull);
    });

    test(
      'validates donation channel requires price 0 and no discountFormat',
      () {
        final valid = CreateListingInput(
          partnerId: 'p1',
          partnerName: 'Resto A',
          title: 'Donasi Malam',
          description: 'Untuk panti asuhan',
          channel: ListingChannel.donation,
          originalPrice: 40000,
          discountedPrice: 0,
          quantity: 10,
          pickupStart: start,
          pickupEnd: end,
        );
        final invalidPrice = CreateListingInput(
          partnerId: 'p1',
          partnerName: 'Resto A',
          title: 'Donasi Malam',
          description: 'Untuk panti asuhan',
          channel: ListingChannel.donation,
          originalPrice: 40000,
          discountedPrice: 5000,
          quantity: 10,
          pickupStart: start,
          pickupEnd: end,
        );

        expect(valid.validate(), isNull);
        expect(invalidPrice.validate(), isNotNull);
      },
    );
  });

  group('Dual-Channel Listing access & workflows', () {
    test(
      'consumer only sees discount listings and cannot claim donation',
      () async {
        final container = _createContainer();
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(listingNotifierProvider.notifier).loadListings();

        final visible = container.read(visibleListingsProvider);
        expect(visible, isNotEmpty);
        expect(
          visible.every((item) => item.channel == ListingChannel.discount),
          isTrue,
        );

        final claimed = await container
            .read(listingNotifierProvider.notifier)
            .claimStock(listingId: 'lst-donation-1', quantity: 1);
        expect(claimed, isFalse);
        expect(
          container.read(listingNotifierProvider).failure,
          isA<ListingPermissionDeniedFailure>(),
        );
      },
    );

    test('verifiedRecipient sees both channels and can claim donation until '
        'soldOut', () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(
            debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
          );
      await container.read(listingNotifierProvider.notifier).loadListings();

      final visible = container.read(visibleListingsProvider);
      expect(
        visible.any((item) => item.channel == ListingChannel.donation),
        isTrue,
      );
      expect(
        visible.any((item) => item.channel == ListingChannel.discount),
        isTrue,
      );

      final ok = await container
          .read(listingNotifierProvider.notifier)
          .claimStock(listingId: 'lst-donation-1', quantity: 15);
      expect(ok, isTrue);

      final updated = container
          .read(listingNotifierProvider)
          .items
          .firstWhere((item) => item.id == 'lst-donation-1');
      expect(updated.remainingQuantity, 0);
      expect(updated.status, ListingStatus.soldOut);
    });

    test(
      'donorPartner creates Flash Sale and converts unsold stock to Donation',
      () async {
        final container = _createContainer();
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();

        final start = DateTime.now().toUtc().add(const Duration(hours: 1));
        final end = start.add(const Duration(hours: 2));

        final created = await container
            .read(listingNotifierProvider.notifier)
            .createListing(
              CreateListingInput(
                partnerId: DummyAuthAccounts.donorPartner.id,
                partnerName: DummyAuthAccounts.donorPartner.displayName,
                title: 'Flash Sale Sushi',
                description: 'Sisa sushi segar menjelang tutup.',
                channel: ListingChannel.discount,
                discountFormat: DiscountFormat.flashSale,
                originalPrice: 100000,
                discountedPrice: 40000,
                quantity: 4,
                pickupStart: start,
                pickupEnd: end,
              ),
            );
        expect(created, isTrue);

        final createdItem = container.read(listingNotifierProvider).items.first;
        expect(createdItem.discountPercent, 60);

        final converted = await container
            .read(listingNotifierProvider.notifier)
            .convertToDonation(createdItem.id);
        expect(converted, isTrue);

        final after = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == createdItem.id);
        expect(after.channel, ListingChannel.donation);
        expect(after.discountedPrice, 0);
        expect(after.discountFormat, isNull);
        expect(after.convertedToDonationAt, isNotNull);

        // Converting an already-donation listing must fail.
        final secondConvert = await container
            .read(listingNotifierProvider.notifier)
            .convertToDonation(createdItem.id);
        expect(secondConvert, isFalse);
        expect(
          container.read(listingNotifierProvider).failure,
          isA<InvalidChannelTransitionFailure>(),
        );
      },
    );

    test('volunteer cannot close donorPartner listing, admin can', () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.volunteer.id);
      await container.read(listingNotifierProvider.notifier).loadListings();

      final denied = await container
          .read(listingNotifierProvider.notifier)
          .closeListing('lst-flash-1');
      expect(denied, isFalse);
      expect(
        container.read(listingNotifierProvider).failure,
        isA<ListingPermissionDeniedFailure>(),
      );

      // Admin can manage any partner's listing.
      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(debugAccountId: DummyAuthAccounts.admin.id);
      final allowed = await container
          .read(listingNotifierProvider.notifier)
          .closeListing('lst-flash-1');
      expect(allowed, isTrue);
    });

    test(
      'auto-expires listing past pickupEnd, blocks claim/convert, and updates '
      'countdown + activeVisibleListingsProvider',
      () async {
        var currentTime = DateTime.utc(2026, 11, 27, 20);
        final tokenStorage = _InMemoryTokenStorage();
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => currentTime),
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(
              DummyAuthRepository(tokenStorage: tokenStorage),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();

        // Keep autoDispose countdown provider subscribed like a live screen.
        final sub = container.listen(
          listingCountdownProvider('lst-flash-1'),
          (_, _) {},
        );
        addTearDown(sub.close);

        // Seeded items have pickup window [21:00, 24:00].
        final initialSnap = container.read(
          listingCountdownProvider('lst-flash-1'),
        );
        expect(initialSnap, isNotNull);
        expect(initialSnap!.phase, PickupPhase.upcoming);
        expect(container.read(activeVisibleListingsProvider), isNotEmpty);

        // Advance clock past 24:00 (2026-11-28 00:05 UTC) and tick.
        currentTime = DateTime.utc(2026, 11, 28, 0, 5);
        await container.refresh(countdownTickerProvider.future);

        final expiredSnap = container.read(
          listingCountdownProvider('lst-flash-1'),
        );
        expect(expiredSnap!.isExpired, isTrue);
        expect(expiredSnap.formattedCountdown, '00:00');

        // Wait for microtask syncExpiredStatuses().
        await Future<void>.delayed(Duration.zero);

        final reconciled = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-flash-1');
        expect(reconciled.status, ListingStatus.expired);
        expect(container.read(activeVisibleListingsProvider), isEmpty);

        // Claiming expired listing returns ListingExpiredFailure.
        final claimed = await container
            .read(listingNotifierProvider.notifier)
            .claimStock(listingId: 'lst-flash-1', quantity: 1);
        expect(claimed, isFalse);
        expect(
          container.read(listingNotifierProvider).failure,
          isA<ListingExpiredFailure>(),
        );

        // Converting expired listing returns InvalidChannelTransitionFailure.
        final converted = await container
            .read(listingNotifierProvider.notifier)
            .convertToDonation('lst-flash-1');
        expect(converted, isFalse);
        expect(
          container.read(listingNotifierProvider).failure,
          isA<InvalidChannelTransitionFailure>(),
        );
      },
    );

    test('enforces daily donation quota on claimStock, protects stock when '
        'exceeded, and distinguishes soldOut from permission denied', () async {
      var now = DateTime.utc(2026, 11, 27, 22);
      final tokenStorage = _InMemoryTokenStorage();
      final kycRepo = InMemoryKycRepository(clock: () => now);
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

      await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle(
            debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
          );
      await container.read(kycNotifierProvider.notifier).loadMyKyc();
      await container.read(listingNotifierProvider.notifier).loadListings();

      // Pre-consume 25 of 30 daily quota -> 5 remaining.
      await kycRepo.consumeDailyQuota(
        userId: DummyAuthAccounts.verifiedRecipient.id,
        quantity: 25,
      );

      // Attempt to claim 6 portions -> exceeds remaining 5, stock untouched!
      final exceeded = await container
          .read(listingNotifierProvider.notifier)
          .claimStock(listingId: 'lst-donation-1', quantity: 6);
      expect(exceeded, isFalse);
      expect(
        container.read(listingNotifierProvider).failure,
        const ListingQuotaExceededFailure(remaining: 5, dailyLimit: 30),
      );
      final untouched = container
          .read(listingNotifierProvider)
          .items
          .firstWhere((item) => item.id == 'lst-donation-1');
      expect(untouched.remainingQuantity, 15);

      // Claim 5 portions -> succeeds & exhausts daily quota.
      final ok = await container
          .read(listingNotifierProvider.notifier)
          .claimStock(listingId: 'lst-donation-1', quantity: 5);
      expect(ok, isTrue);
      expect(container.read(dailyQuotaProvider)?.remaining, 0);

      // Next UTC day (00:30, still inside cross-midnight pickup window) ->
      // quota resets to 30, can claim remaining 10 -> soldOut.
      now = DateTime.utc(2026, 11, 28, 0, 30);
      final claimRest = await container
          .read(listingNotifierProvider.notifier)
          .claimStock(listingId: 'lst-donation-1', quantity: 10);
      expect(claimRest, isTrue);

      // Claiming a soldOut listing returns InsufficientStockFailure.
      final afterSoldOut = await container
          .read(listingNotifierProvider.notifier)
          .claimStock(listingId: 'lst-donation-1', quantity: 1);
      expect(afterSoldOut, isFalse);
      expect(
        container.read(listingNotifierProvider).failure,
        isA<InsufficientStockFailure>(),
      );
    });

    test(
      'partner publishes direct donation with originalPrice=0 (no flashSale) '
      'and sees own donation in feed without self-claim; volunteer hides '
      'unclaimable donations',
      () async {
        final now = DateTime.now().toUtc();
        final container = _createContainer();
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();

        final ok = await container
            .read(listingNotifierProvider.notifier)
            .createListing(
              CreateListingInput(
                partnerId: DummyAuthAccounts.donorPartner.id,
                partnerName: DummyAuthAccounts.donorPartner.displayName,
                title: 'Donasi Langsung Nasi Kotak',
                description: 'Langsung didonasikan tanpa flash sale',
                channel: ListingChannel.donation,
                originalPrice: 0,
                discountedPrice: 0,
                quantity: 12,
                pickupStart: now.add(const Duration(minutes: 15)),
                pickupEnd: now.add(const Duration(hours: 3)),
              ),
            );
        expect(ok, isTrue);

        // Partner sees their own donation listing in Beranda for management.
        final partnerVisible = container.read(visibleListingsProvider);
        final ownDonation = partnerVisible.firstWhere(
          (item) => item.title == 'Donasi Langsung Nasi Kotak',
        );
        expect(ownDonation.channel, ListingChannel.donation);
        expect(ownDonation.originalPrice, 0);
        expect(ownDonation.discountFormat, isNull);

        // Partner cannot claim/book their own listing.
        final selfClaim = await container
            .read(listingNotifierProvider.notifier)
            .claimStock(listingId: ownDonation.id, quantity: 1);
        expect(selfClaim, isFalse);
        expect(
          container.read(listingNotifierProvider).failure,
          isA<ListingPermissionDeniedFailure>(),
        );

        // Volunteer cannot claim donations -> hidden from Beranda.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.volunteer.id);
        final volunteerVisible = container.read(visibleListingsProvider);
        expect(
          volunteerVisible.any(
            (item) => item.channel == ListingChannel.donation,
          ),
          isFalse,
        );
      },
    );
  });
}
