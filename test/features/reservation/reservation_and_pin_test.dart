import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/kyc/presentation/provider/kyc_provider.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_failure.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
import 'package:surplus_share/features/reservation/domain/policy/reservation_policy.dart';
import 'package:surplus_share/features/reservation/presentation/provider/reservation_provider.dart';

class _InMemoryTokenStorage implements TokenStorage {
  AuthTokens? _tokens;

  @override
  Future<void> clearTokens() async => _tokens = null;

  @override
  Future<String?> getAccessToken() async => _tokens?.accessToken;

  @override
  Future<String?> getRefreshToken() async => _tokens?.refreshToken;

  @override
  Future<AuthTokens?> getTokens() async => _tokens;

  @override
  Future<void> saveTokens(AuthTokens tokens) async => _tokens = tokens;
}

ProviderContainer _createContainer(Clock clock) {
  final tokenStorage = _InMemoryTokenStorage();
  return ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(clock),
      tokenStorageProvider.overrideWithValue(tokenStorage),
      authRepositoryProvider.overrideWithValue(
        DummyAuthRepository(tokenStorage: tokenStorage),
      ),
    ],
  );
}

void main() {
  group('Discount reservation, WebView payment & PIN handover', () {
    test(
      'holds stock, generates HTTPS payment URL, issues 6-digit PIN on '
      'confirm, and creates HandoverReceipt on staff PIN validation',
      () async {
        final now = DateTime.utc(2026, 11, 27, 18);
        final container = _createContainer(() => now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(listingNotifierProvider.notifier).loadListings();

        final listing = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-flash-1');
        expect(listing.remainingQuantity, 6);

        // Book 2 portions with QRIS -> stock held immediately (6 -> 4).
        final pending = await container
            .read(reservationNotifierProvider.notifier)
            .bookDiscount(
              listing: listing,
              quantity: 2,
              paymentMethod: PaymentMethod.qris,
            );
        expect(pending, isNotNull);
        expect(pending!.status, ReservationStatus.pendingPayment);
        expect(pending.pickupPin, isNull);
        expect(pending.paymentSession, isNotNull);
        expect(pending.paymentSession!.isSecureUrl, isTrue);
        expect(pending.totalAmount, 40000);

        final afterHold = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-flash-1');
        expect(afterHold.remainingQuantity, 4);

        // Confirm payment -> status confirmed + 6-digit PIN issued.
        final paid = await container
            .read(reservationNotifierProvider.notifier)
            .confirmPayment(pending.id);
        expect(paid, isTrue);

        final confirmed = container
            .read(reservationNotifierProvider)
            .items
            .firstWhere((r) => r.id == pending.id);
        expect(confirmed.status, ReservationStatus.confirmed);
        expect(confirmed.pickupPin, isNotNull);
        expect(confirmed.pickupPin!.length, ReservationPolicy.pinLength);
        expect(confirmed.toString(), isNot(contains(confirmed.pickupPin)));

        // Partner logs in and validates PIN on-site -> completed + receipt.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container
            .read(reservationNotifierProvider.notifier)
            .loadPartnerReservations();

        final validated = await container
            .read(reservationNotifierProvider.notifier)
            .validatePickupPin(
              reservationId: confirmed.id,
              pin: confirmed.pickupPin!,
            );
        expect(validated, isTrue);

        final completed = container
            .read(reservationNotifierProvider)
            .items
            .firstWhere((r) => r.id == confirmed.id);
        expect(completed.status, ReservationStatus.completed);
        expect(completed.pickupPin, isNull);
        expect(completed.receipt, isNotNull);
        expect(
          completed.receipt!.verifiedByStaffId,
          DummyAuthAccounts.donorPartner.id,
        );
      },
    );

    test(
      'prevents double booking and releases stock when payment expires (15m)',
      () async {
        var now = DateTime.utc(2026, 11, 27, 18);
        final container = _createContainer(() => now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(listingNotifierProvider.notifier).loadListings();

        final listing = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-flash-1');

        // Book all 6 remaining portions.
        final first = await container
            .read(reservationNotifierProvider.notifier)
            .bookDiscount(
              listing: listing,
              quantity: 6,
              paymentMethod: PaymentMethod.eWallet,
            );
        expect(first, isNotNull);

        // Second booking fails (anti double-booking).
        final second = await container
            .read(reservationNotifierProvider.notifier)
            .bookDiscount(
              listing: listing,
              quantity: 1,
              paymentMethod: PaymentMethod.qris,
            );
        expect(second, isNull);
        expect(
          container.read(reservationNotifierProvider).failure,
          isA<ReservationStockUnavailableFailure>(),
        );

        // Advance clock by 16 minutes -> payment expires & stock released!
        now = now.add(const Duration(minutes: 16));
        final lateConfirm = await container
            .read(reservationNotifierProvider.notifier)
            .confirmPayment(first!.id);
        expect(lateConfirm, isFalse);
        expect(
          container.read(reservationNotifierProvider).failure,
          isA<PaymentExpiredFailure>(),
        );

        final restoredListing = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-flash-1');
        expect(restoredListing.remainingQuantity, 6);
      },
    );
  });

  group('Donation reservation, quota refund & PIN security', () {
    test(
      'donation booking consumes quota + issues PIN, and cancellation refunds '
      'both stock and daily quota',
      () async {
        final now = DateTime.utc(2026, 11, 27, 18);
        final container = _createContainer(() => now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
            );
        await container.read(kycNotifierProvider.notifier).loadMyKyc();
        await container.read(listingNotifierProvider.notifier).loadListings();

        final donationListing = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-donation-1');

        final booked = await container
            .read(reservationNotifierProvider.notifier)
            .bookDonation(listing: donationListing, quantity: 5);
        expect(booked, isNotNull);
        expect(booked!.status, ReservationStatus.confirmed);
        expect(booked.pickupPin, isNotNull);
        expect(container.read(dailyQuotaProvider)?.remaining, 25);

        // Cancel reservation -> stock restored (10 -> 15) & quota refunded.
        final cancelled = await container
            .read(reservationNotifierProvider.notifier)
            .cancelReservation(booked.id);
        expect(cancelled, isTrue);
        expect(container.read(dailyQuotaProvider)?.remaining, 30);

        final restored = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-donation-1');
        expect(restored.remainingQuantity, 15);
      },
    );

    test(
      'locks PIN after 5 wrong attempts and rejects non-owner staff',
      () async {
        final now = DateTime.utc(2026, 11, 27, 18);
        final container = _createContainer(() => now);
        addTearDown(container.dispose);

        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.verifiedRecipient.id,
            );
        await container.read(listingNotifierProvider.notifier).loadListings();

        final donationListing = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-donation-1');
        final booked = await container
            .read(reservationNotifierProvider.notifier)
            .bookDonation(listing: donationListing, quantity: 2);
        final wrongPin = booked!.pickupPin == '000000' ? '111111' : '000000';

        // Non-owner partnerStaff is denied (isolated from other partners).
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.partnerStaff.id,
            );
        await container
            .read(reservationNotifierProvider.notifier)
            .loadPartnerReservations();
        final denied = await container
            .read(reservationNotifierProvider.notifier)
            .validatePickupPin(
              reservationId: booked.id,
              pin: booked.pickupPin!,
            );
        expect(denied, isFalse);
        expect(
          container.read(reservationNotifierProvider).failure,
          anyOf(
            isA<ReservationPermissionDeniedFailure>(),
            isA<ReservationNotFoundFailure>(),
          ),
        );

        // Owner partner enters wrong PIN 5 times -> locked on 5th attempt.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container
            .read(reservationNotifierProvider.notifier)
            .loadPartnerReservations();

        for (var i = 1; i <= 4; i++) {
          final ok = await container
              .read(reservationNotifierProvider.notifier)
              .validatePickupPin(reservationId: booked.id, pin: wrongPin);
          expect(ok, isFalse);
          expect(
            container.read(reservationNotifierProvider).failure,
            InvalidPinFailure(remainingAttempts: 5 - i),
          );
        }

        final fifth = await container
            .read(reservationNotifierProvider.notifier)
            .validatePickupPin(reservationId: booked.id, pin: wrongPin);
        expect(fifth, isFalse);
        expect(
          container.read(reservationNotifierProvider).failure,
          isA<PinLockedFailure>(),
        );

        // Even the correct PIN is rejected once locked.
        final afterLock = await container
            .read(reservationNotifierProvider.notifier)
            .validatePickupPin(
              reservationId: booked.id,
              pin: booked.pickupPin!,
            );
        expect(afterLock, isFalse);
        expect(
          container.read(reservationNotifierProvider).failure,
          isA<PinLockedFailure>(),
        );
      },
    );
  });
}
