import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/features/impact/domain/models/impact_summary.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/listing_channel.dart';
import 'package:surplus_share/features/reservation/domain/models/handover_receipt.dart';

/// Single source of truth for rescued food weight, CO2e avoidance, and
/// gamification badge calculation.
abstract final class ImpactCalculator {
  /// Standard FAO/WRAP average CO2e avoided per 1 kg of rescued food.
  static const double co2KgPerKgFood = 2.5;
  static const double defaultWeightPerPortionKg = 0.40;

  static double weightPerPortionKg(FoodCategory? category) {
    return switch (category) {
      FoodCategory.readyToEat => 0.45,
      FoodCategory.bakery => 0.30,
      FoodCategory.rawIngredients => 0.50,
      FoodCategory.beverages => 0.35,
      null => defaultWeightPerPortionKg,
    };
  }

  static bool canExportCsrReport(Set<Permission> permissions) {
    return permissions.contains(Permission.exportCsrReport);
  }

  /// Aggregates [receipts] in a single O(n) pass, optionally scoped to
  /// `[periodStart, periodEnd]`.
  static ImpactSummary computeSummary({
    required Iterable<HandoverReceipt> receipts,
    Map<String, FoodCategory> categoryByListingId = const {},
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final startUtc = periodStart?.toUtc();
    final endUtc = periodEnd?.toUtc();

    var totalPortions = 0;
    var discountPortions = 0;
    var donationPortions = 0;
    var totalFoodSavedKg = 0.0;
    var completedHandovers = 0;
    var totalDiscountValueIdr = 0;

    for (final receipt in receipts) {
      final handedAt = receipt.handedOverAt.toUtc();
      if (startUtc != null && handedAt.isBefore(startUtc)) continue;
      if (endUtc != null && handedAt.isAfter(endUtc)) continue;

      completedHandovers++;
      totalPortions += receipt.quantity;
      if (receipt.channel == ListingChannel.donation) {
        donationPortions += receipt.quantity;
      } else {
        discountPortions += receipt.quantity;
        totalDiscountValueIdr += receipt.totalAmount;
      }

      final category = categoryByListingId[receipt.listingId];
      totalFoodSavedKg += receipt.quantity * weightPerPortionKg(category);
    }

    final roundedFoodKg = _round2(totalFoodSavedKg);
    final co2AvoidedKg = _round2(roundedFoodKg * co2KgPerKgFood);
    final badge = _resolveBadge(totalPortions);

    return ImpactSummary(
      totalPortions: totalPortions,
      discountPortions: discountPortions,
      donationPortions: donationPortions,
      totalFoodSavedKg: roundedFoodKg,
      co2AvoidedKg: co2AvoidedKg,
      completedHandovers: completedHandovers,
      totalDiscountValueIdr: totalDiscountValueIdr,
      badgeLevel: badge.current,
      nextBadge: badge.next,
      portionsToNextBadge: badge.portionsRemaining,
      badgeProgress: badge.progress,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  static ({
    ImpactBadgeLevel current,
    ImpactBadgeLevel? next,
    int portionsRemaining,
    double progress,
  })
  _resolveBadge(int totalPortions) {
    const levels = ImpactBadgeLevel.values;
    var currentIndex = 0;
    for (var i = 0; i < levels.length; i++) {
      if (totalPortions >= levels[i].minPortions) {
        currentIndex = i;
      }
    }

    final current = levels[currentIndex];
    if (currentIndex == levels.length - 1) {
      return (current: current, next: null, portionsRemaining: 0, progress: 1);
    }

    final next = levels[currentIndex + 1];
    final span = next.minPortions - current.minPortions;
    final earnedInTier = totalPortions - current.minPortions;
    final progress = (earnedInTier / span).clamp(0.0, 1.0);
    return (
      current: current,
      next: next,
      portionsRemaining: next.minPortions - totalPortions,
      progress: _round2(progress),
    );
  }

  static double _round2(double value) => (value * 100).round() / 100;
}
