import 'dart:math';

import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/features/reservation/domain/models/reservation.dart';

/// Pure domain rules for reservation PIN generation, verification, and access.
abstract final class ReservationPolicy {
  static const int pinLength = 6;
  static const int maxPinAttempts = 5;
  static const Duration paymentTimeout = Duration(minutes: 15);

  static final Random _secureRandom = Random.secure();

  /// Generates a cryptographically secure 6-digit PIN unique within
  /// [activePins].
  static String generateUniquePin(Set<String> activePins) {
    for (var attempt = 0; attempt < 50; attempt++) {
      final value = _secureRandom.nextInt(1000000);
      final pin = value.toString().padLeft(pinLength, '0');
      if (!activePins.contains(pin)) return pin;
    }
    throw StateError('Gagal menghasilkan PIN unik.');
  }

  /// Constant-time comparison to avoid timing side-channels when verifying PIN.
  static bool verifyPinConstantTime(String expected, String actual) {
    final normalizedActual = actual.trim();
    if (expected.length != normalizedActual.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ normalizedActual.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Checks whether the staff/partner/admin is allowed to validate handover PIN
  /// for [reservation].
  static bool canValidateHandover(
    Reservation reservation, {
    required String? actorUserId,
    required AppRole role,
    required Set<Permission> permissions,
  }) {
    if (!permissions.contains(Permission.validatePickupPin)) return false;
    if (role == AppRole.admin) return true;
    return actorUserId != null && reservation.partnerId == actorUserId;
  }

  /// Computes payment expiration capped at [pickupEnd] so payment cannot
  /// outlive the food pickup window.
  static DateTime computePaymentExpiry({
    required DateTime now,
    required DateTime pickupEnd,
  }) {
    final defaultExpiry = now.toUtc().add(paymentTimeout);
    final endUtc = pickupEnd.toUtc();
    return defaultExpiry.isBefore(endUtc) ? defaultExpiry : endUtc;
  }
}
