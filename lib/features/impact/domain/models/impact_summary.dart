import 'package:flutter/foundation.dart';

enum ImpactBadgeLevel {
  starter(minPortions: 0, label: 'Food Saver Pemula'),
  rescuer(minPortions: 10, label: 'Penyelamat Pangan'),
  guardian(minPortions: 50, label: 'Penjaga Bumi'),
  champion(minPortions: 150, label: 'Juara Zero Waste'),
  hero(minPortions: 500, label: 'Pahlawan Zero Hunger');

  new({required this.minPortions, required this.label});

  final int minPortions;
  final String label;
}

@immutable
class ImpactSummary {
  const new({
    required this.totalPortions,
    required this.discountPortions,
    required this.donationPortions,
    required this.totalFoodSavedKg,
    required this.co2AvoidedKg,
    required this.completedHandovers,
    required this.totalDiscountValueIdr,
    required this.badgeLevel,
    required this.portionsToNextBadge,
    required this.badgeProgress,
    this.nextBadge,
    this.periodStart,
    this.periodEnd,
  });

  final int totalPortions;
  final int discountPortions;
  final int donationPortions;
  final double totalFoodSavedKg;
  final double co2AvoidedKg;
  final int completedHandovers;
  final int totalDiscountValueIdr;
  final ImpactBadgeLevel badgeLevel;
  final ImpactBadgeLevel? nextBadge;
  final int portionsToNextBadge;
  final double badgeProgress;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ImpactSummary &&
        other.totalPortions == totalPortions &&
        other.discountPortions == discountPortions &&
        other.donationPortions == donationPortions &&
        other.totalFoodSavedKg == totalFoodSavedKg &&
        other.co2AvoidedKg == co2AvoidedKg &&
        other.completedHandovers == completedHandovers &&
        other.totalDiscountValueIdr == totalDiscountValueIdr &&
        other.badgeLevel == badgeLevel &&
        other.nextBadge == nextBadge &&
        other.portionsToNextBadge == portionsToNextBadge &&
        other.badgeProgress == badgeProgress &&
        other.periodStart == periodStart &&
        other.periodEnd == periodEnd;
  }

  @override
  int get hashCode => Object.hash(
    totalPortions,
    discountPortions,
    donationPortions,
    totalFoodSavedKg,
    co2AvoidedKg,
    completedHandovers,
    totalDiscountValueIdr,
    badgeLevel,
    nextBadge,
    portionsToNextBadge,
    badgeProgress,
    periodStart,
    periodEnd,
  );
}
