import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/food_safety_declaration.dart';
import 'package:surplus_share/features/listing/domain/models/surplus_listing.dart';

@immutable
class FoodSafetyFilter {
  const new({
    this.halalOnly = false,
    this.halalCertifiedOnly = false,
    this.excludedAllergens = const <FoodAllergen>{},
    this.categories = const <FoodCategory>{},
  });

  factory fromJson(Map<String, dynamic> json) {
    final rawAllergens = json['excluded_allergens'];
    final rawCategories = json['categories'];

    final allergens = <FoodAllergen>{};
    if (rawAllergens is List) {
      for (final name in rawAllergens.whereType<String>()) {
        for (final value in FoodAllergen.values) {
          if (value.name == name) allergens.add(value);
        }
      }
    }

    final categories = <FoodCategory>{};
    if (rawCategories is List) {
      for (final name in rawCategories.whereType<String>()) {
        for (final value in FoodCategory.values) {
          if (value.name == name) categories.add(value);
        }
      }
    }

    return FoodSafetyFilter(
      halalOnly: json['halal_only'] == true,
      halalCertifiedOnly: json['halal_certified_only'] == true,
      excludedAllergens: Set<FoodAllergen>.unmodifiable(allergens),
      categories: Set<FoodCategory>.unmodifiable(categories),
    );
  }

  final bool halalOnly;
  final bool halalCertifiedOnly;
  final Set<FoodAllergen> excludedAllergens;
  final Set<FoodCategory> categories;

  bool get isActive =>
      halalOnly ||
      halalCertifiedOnly ||
      excludedAllergens.isNotEmpty ||
      categories.isNotEmpty;

  /// Evaluates whether [listing] satisfies the user's dietary and safety
  /// preferences.
  ///
  /// Fail-safe: when any safety/dietary filter is active, listings lacking a
  /// [FoodSafetyDeclaration] are excluded to protect consumer health.
  bool matches(SurplusListing listing) {
    if (!isActive) return true;

    final safety = listing.foodSafety;
    if (safety == null) return false;

    if (halalCertifiedOnly &&
        safety.halalStatus != HalalStatus.halalCertified) {
      return false;
    }
    if (halalOnly && !safety.halalStatus.isHalal) {
      return false;
    }
    if (excludedAllergens.isNotEmpty &&
        safety.containsAnyAllergen(excludedAllergens)) {
      return false;
    }
    if (categories.isNotEmpty && !categories.contains(safety.category)) {
      return false;
    }
    return true;
  }

  FoodSafetyFilter copyWith({
    bool? halalOnly,
    bool? halalCertifiedOnly,
    Set<FoodAllergen>? excludedAllergens,
    Set<FoodCategory>? categories,
  }) {
    return FoodSafetyFilter(
      halalOnly: halalOnly ?? this.halalOnly,
      halalCertifiedOnly: halalCertifiedOnly ?? this.halalCertifiedOnly,
      excludedAllergens: excludedAllergens ?? this.excludedAllergens,
      categories: categories ?? this.categories,
    );
  }

  Map<String, dynamic> toJson() => {
    'halal_only': halalOnly,
    'halal_certified_only': halalCertifiedOnly,
    'excluded_allergens': [for (final a in excludedAllergens) a.name],
    'categories': [for (final c in categories) c.name],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FoodSafetyFilter &&
        other.halalOnly == halalOnly &&
        other.halalCertifiedOnly == halalCertifiedOnly &&
        setEquals(other.excludedAllergens, excludedAllergens) &&
        setEquals(other.categories, categories);
  }

  @override
  int get hashCode => Object.hash(
    halalOnly,
    halalCertifiedOnly,
    Object.hashAllUnordered(excludedAllergens),
    Object.hashAllUnordered(categories),
  );
}
