import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/time/clock_provider.dart';
import 'package:surplus_share/features/impact/domain/models/impact_failure.dart';
import 'package:surplus_share/features/impact/domain/models/impact_summary.dart';
import 'package:surplus_share/features/impact/domain/policy/impact_calculator.dart';
import 'package:surplus_share/features/impact/presentation/provider/impact_provider.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/listing/presentation/provider/listing_provider.dart';
import 'package:surplus_share/features/reservation/domain/models/handover_receipt.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation_status.dart';
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

HandoverReceipt _receipt({
  required String id,
  required String listingId,
  required ListingChannel channel,
  required int quantity,
  required DateTime handedOverAt,
  int totalAmount = 0,
}) {
  return HandoverReceipt(
    receiptId: id,
    reservationId: 'res-$id',
    listingId: listingId,
    listingTitle: 'Item $id',
    partnerId: 'p1',
    customerId: 'u1',
    verifiedByStaffId: 'p1',
    channel: channel,
    quantity: quantity,
    totalAmount: totalAmount,
    handedOverAt: handedOverAt,
  );
}

void main() {
  group('ImpactCalculator & Gamification Badges', () {
    test('computes kg, FAO CO2e (2.5x), channel split, and period filter', () {
      final d1 = DateTime.utc(2026, 11, 10, 12);
      final d2 = DateTime.utc(2026, 11, 20, 12);
      final outside = DateTime.utc(2026, 10, 1, 12);

      final summary = ImpactCalculator.computeSummary(
        receipts: [
          _receipt(
            id: 'r1',
            listingId: 'l-ready',
            channel: ListingChannel.discount,
            quantity: 4, // 4 * 0.45 = 1.80 kg
            totalAmount: 80000,
            handedOverAt: d1,
          ),
          _receipt(
            id: 'r2',
            listingId: 'l-bakery',
            channel: ListingChannel.donation,
            quantity: 10, // 10 * 0.30 = 3.00 kg
            handedOverAt: d2,
          ),
          _receipt(
            id: 'r3',
            listingId: 'l-ready',
            channel: ListingChannel.discount,
            quantity: 20,
            totalAmount: 400000,
            handedOverAt: outside,
          ),
        ],
        categoryByListingId: const {
          'l-ready': FoodCategory.readyToEat,
          'l-bakery': FoodCategory.bakery,
        },
        periodStart: DateTime.utc(2026, 11),
        periodEnd: DateTime.utc(2026, 11, 30),
      );

      expect(summary.completedHandovers, 2);
      expect(summary.totalPortions, 14);
      expect(summary.discountPortions, 4);
      expect(summary.donationPortions, 10);
      expect(summary.totalDiscountValueIdr, 80000);
      expect(summary.totalFoodSavedKg, 4.8);
      expect(summary.co2AvoidedKg, 12.0); // 4.8 * 2.5
      expect(summary.badgeLevel, ImpactBadgeLevel.rescuer);
      expect(summary.nextBadge, ImpactBadgeLevel.guardian);
      expect(summary.portionsToNextBadge, 36);
    });

    test('resolves all gamification badge tiers up to hero (500+)', () {
      ImpactSummary forPortions(int count) => ImpactCalculator.computeSummary(
        receipts: [
          if (count > 0)
            _receipt(
              id: 'r',
              listingId: 'l',
              channel: ListingChannel.discount,
              quantity: count,
              handedOverAt: DateTime.utc(2026, 11, 27),
            ),
        ],
      );

      expect(forPortions(0).badgeLevel, ImpactBadgeLevel.starter);
      expect(forPortions(10).badgeLevel, ImpactBadgeLevel.rescuer);
      expect(forPortions(50).badgeLevel, ImpactBadgeLevel.guardian);
      expect(forPortions(150).badgeLevel, ImpactBadgeLevel.champion);

      final hero = forPortions(520);
      expect(hero.badgeLevel, ImpactBadgeLevel.hero);
      expect(hero.nextBadge, isNull);
      expect(hero.portionsToNextBadge, 0);
      expect(hero.badgeProgress, 1.0);
    });
  });

  group('End-to-end Handover -> Impact Tracker -> CSR PDF Export', () {
    test(
      'tracks completed PIN handover in user & partner impact, blocks consumer '
      'CSR export, and generates valid %PDF- for donorPartner',
      () async {
        final now = DateTime.utc(2026, 11, 27, 18);
        final tokenStorage = _InMemoryTokenStorage();
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            tokenStorageProvider.overrideWithValue(tokenStorage),
            authRepositoryProvider.overrideWithValue(
              DummyAuthRepository(tokenStorage: tokenStorage),
            ),
          ],
        );
        addTearDown(container.dispose);

        // 1. Consumer books 2 portions of lst-flash-1 (readyToEat: 0.45 kg)
        //    and confirms payment.
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(debugAccountId: DummyAuthAccounts.consumer.id);
        await container.read(listingNotifierProvider.notifier).loadListings();
        final listing = container
            .read(listingNotifierProvider)
            .items
            .firstWhere((item) => item.id == 'lst-flash-1');

        final booked = await container
            .read(reservationNotifierProvider.notifier)
            .bookDiscount(
              listing: listing,
              quantity: 2,
              paymentMethod: PaymentMethod.qris,
            );
        await container
            .read(reservationNotifierProvider.notifier)
            .confirmPayment(booked!.id);
        final confirmed = container
            .read(reservationNotifierProvider)
            .items
            .firstWhere((r) => r.id == booked.id);

        // Consumer cannot export CSR PDF.
        final deniedBytes = await container
            .read(csrReportNotifierProvider.notifier)
            .exportPartnerCsrPdf(
              organizationName: 'Test',
              periodStart: DateTime.utc(2026, 11),
              periodEnd: DateTime.utc(2026, 11, 30),
            );
        expect(deniedBytes, isNull);
        expect(
          container.read(csrReportNotifierProvider).failure,
          isA<ImpactPermissionDeniedFailure>(),
        );

        // 2. Partner validates PIN -> creates HandoverReceipt!
        await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle(
              debugAccountId: DummyAuthAccounts.donorPartner.id,
            );
        await container
            .read(reservationNotifierProvider.notifier)
            .loadPartnerReservations();
        await container
            .read(reservationNotifierProvider.notifier)
            .validatePickupPin(
              reservationId: confirmed.id,
              pin: confirmed.pickupPin!,
            );

        // Partner impact summary updates reactively:
        // 2 * 0.45 = 0.90 kg food, 0.90 * 2.5 = 2.25 kg CO2e.
        final partnerImpact = container.read(
          partnerImpactSummaryProvider((
            start: DateTime.utc(2026, 11),
            end: DateTime.utc(2026, 11, 30),
          )),
        );
        expect(partnerImpact.totalPortions, 2);
        expect(partnerImpact.totalFoodSavedKg, 0.9);
        expect(partnerImpact.co2AvoidedKg, 2.25);

        // 3. Partner exports official CSR/ESG PDF -> valid %PDF- bytes!
        final pdfBytes = await container
            .read(csrReportNotifierProvider.notifier)
            .exportPartnerCsrPdf(
              organizationName: DummyAuthAccounts.donorPartner.displayName,
              periodStart: DateTime.utc(2026, 11),
              periodEnd: DateTime.utc(2026, 11, 30),
            );
        expect(pdfBytes, isNotNull);
        expect(pdfBytes!.length, greaterThan(500));
        expect(utf8.decode(pdfBytes.sublist(0, 5)), '%PDF-');
        expect(
          container.read(csrReportNotifierProvider).lastReportData?.receipts,
          hasLength(1),
        );
      },
    );
  });
}
