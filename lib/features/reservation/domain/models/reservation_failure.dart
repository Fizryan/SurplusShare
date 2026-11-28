import 'package:flutter/foundation.dart';

@immutable
sealed class ReservationFailure {
  const new(this.message);

  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other.runtimeType == runtimeType &&
        other is ReservationFailure &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => 'ReservationFailure($message)';
}

final class ReservationValidationFailure extends ReservationFailure {
  const new(super.message);

  @override
  String toString() => 'ReservationValidationFailure($message)';
}

final class ReservationPermissionDeniedFailure extends ReservationFailure {
  const new([super.message = 'Anda tidak memiliki izin untuk aksi ini.']);

  @override
  String toString() => 'ReservationPermissionDeniedFailure($message)';
}

final class ReservationNotFoundFailure extends ReservationFailure {
  const new([super.message = 'Reservasi tidak ditemukan.']);

  @override
  String toString() => 'ReservationNotFoundFailure($message)';
}

final class ReservationStockUnavailableFailure extends ReservationFailure {
  const new([super.message = 'Stok makanan tidak mencukupi atau habis.']);

  @override
  String toString() => 'ReservationStockUnavailableFailure($message)';
}

final class ReservationQuotaExceededFailure extends ReservationFailure {
  const new({required this.remaining, required this.dailyLimit})
    : super(
        'Kuota donasi harian tersisa $remaining porsi '
        'dari batas $dailyLimit porsi/hari.',
      );

  final int remaining;
  final int dailyLimit;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReservationQuotaExceededFailure &&
        other.remaining == remaining &&
        other.dailyLimit == dailyLimit;
  }

  @override
  int get hashCode => Object.hash(runtimeType, remaining, dailyLimit);
}

final class PaymentExpiredFailure extends ReservationFailure {
  const new([
    super.message =
        'Batas waktu pembayaran telah berakhir. Stok telah '
        'dikembalikan.',
  ]);

  @override
  String toString() => 'PaymentExpiredFailure($message)';
}

final class InvalidPinFailure extends ReservationFailure {
  const new({required this.remainingAttempts})
    : super('Kode PIN tidak sesuai. Sisa percobaan: $remainingAttempts.');

  final int remainingAttempts;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InvalidPinFailure &&
        other.remainingAttempts == remainingAttempts;
  }

  @override
  int get hashCode => Object.hash(runtimeType, remainingAttempts);
}

final class PinLockedFailure extends ReservationFailure {
  const new([
    super.message =
        'Validasi PIN terkunci karena terlalu banyak percobaan '
        'salah.',
  ]);

  @override
  String toString() => 'PinLockedFailure($message)';
}

final class ReservationPickupExpiredFailure extends ReservationFailure {
  const new([
    super.message = 'Batas waktu pengambilan reservasi telah berakhir.',
  ]);

  @override
  String toString() => 'ReservationPickupExpiredFailure($message)';
}

final class InvalidReservationTransitionFailure extends ReservationFailure {
  const new([super.message = 'Status reservasi tidak mengizinkan aksi ini.']);

  @override
  String toString() => 'InvalidReservationTransitionFailure($message)';
}
