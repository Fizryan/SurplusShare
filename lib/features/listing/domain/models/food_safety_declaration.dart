import 'package:flutter/foundation.dart';
import 'package:surplus_share/features/listing/domain/models/pickup_window.dart';

enum HalalStatus {
  halalCertified,
  halalFriendly,
  nonHalal;

  bool get isHalal => this != HalalStatus.nonHalal;
}

enum FoodCategory { readyToEat, bakery, rawIngredients, beverages }

enum FoodAllergen { peanuts, dairy, seafood, eggs, gluten, soy }

@immutable
class FoodSafetyDeclaration {
  const new({
    required this.halalStatus,
    required this.category,
    required this.safeUntil,
    required this.hygieneConfirmed,
    this.allergens = const <FoodAllergen>{},
    this.storageNote,
  });

  factory fromJson(Map<String, dynamic> json) {
    final halalName = json['halal_status'] as String?;
    final categoryName = json['category'] as String?;
    final rawAllergens = json['allergens'];
    final parsedAllergens = <FoodAllergen>{};
    if (rawAllergens is List) {
      for (final name in rawAllergens.whereType<String>()) {
        for (final a in FoodAllergen.values) {
          if (a.name == name) parsedAllergens.add(a);
        }
      }
    }

    return FoodSafetyDeclaration(
      halalStatus: HalalStatus.values.firstWhere(
        (v) => v.name == halalName,
        orElse: () => HalalStatus.halalFriendly,
      ),
      category: FoodCategory.values.firstWhere(
        (v) => v.name == categoryName,
        orElse: () => FoodCategory.readyToEat,
      ),
      allergens: Set<FoodAllergen>.unmodifiable(parsedAllergens),
      safeUntil: DateTime.parse(json['safe_until'] as String).toUtc(),
      hygieneConfirmed: json['hygiene_confirmed'] == true,
      storageNote: json['storage_note'] as String?,
    );
  }

  static const Duration maxSafeAfterPickup = Duration(hours: 72);

  final HalalStatus halalStatus;
  final FoodCategory category;
  final Set<FoodAllergen> allergens;
  final DateTime safeUntil;
  final bool hygieneConfirmed;
  final String? storageNote;

  bool isSafeToConsume({DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    return reference.isBefore(safeUntil.toUtc());
  }

  bool containsAnyAllergen(Set<FoodAllergen> excluded) {
    return allergens.any(excluded.contains);
  }

  /// Validates partner hygiene declaration and safe consumption window.
  String? validate({required PickupWindow pickupWindow, DateTime? now}) {
    if (!hygieneConfirmed) {
      return 'Mitra wajib mengonfirmasi keamanan dan higienitas makanan.';
    }

    final safeUtc = safeUntil.toUtc();
    final pickupEndUtc = pickupWindow.end.toUtc();
    final reference = (now ?? DateTime.now()).toUtc();

    if (!safeUtc.isAfter(reference)) {
      return 'Estimasi waktu aman konsumsi tidak boleh di masa lalu.';
    }
    if (safeUtc.isBefore(pickupEndUtc)) {
      return 'Estimasi waktu aman konsumsi tidak boleh lebih awal dari '
          'batas waktu pengambilan.';
    }
    if (safeUtc.difference(pickupEndUtc) > maxSafeAfterPickup) {
      return 'Estimasi waktu aman konsumsi maksimal '
          '${maxSafeAfterPickup.inHours} jam setelah batas pengambilan.';
    }

    return null;
  }

  Map<String, dynamic> toJson() => {
    'halal_status': halalStatus.name,
    'category': category.name,
    'allergens': [for (final a in allergens) a.name],
    'safe_until': safeUntil.toUtc().toIso8601String(),
    'hygiene_confirmed': hygieneConfirmed,
    'storage_note': storageNote,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FoodSafetyDeclaration &&
        other.halalStatus == halalStatus &&
        other.category == category &&
        setEquals(other.allergens, allergens) &&
        other.safeUntil.toUtc() == safeUntil.toUtc() &&
        other.hygieneConfirmed == hygieneConfirmed &&
        other.storageNote == storageNote;
  }

  @override
  int get hashCode => Object.hash(
    halalStatus,
    category,
    Object.hashAllUnordered(allergens),
    safeUntil.toUtc(),
    hygieneConfirmed,
    storageNote,
  );
}
