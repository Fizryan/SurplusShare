import 'package:flutter/foundation.dart';

@immutable
sealed class ListingFailure {
  const new(this.message);

  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other.runtimeType == runtimeType &&
        other is ListingFailure &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => 'ListingFailure($message)';
}

final class ListingValidationFailure extends ListingFailure {
  const new(super.message);

  @override
  String toString() => 'ListingValidationFailure($message)';
}

final class ListingPermissionDeniedFailure extends ListingFailure {
  const new([super.message = 'Anda tidak memiliki izin untuk aksi ini.']);

  @override
  String toString() => 'ListingPermissionDeniedFailure($message)';
}

final class ListingNotFoundFailure extends ListingFailure {
  const new([super.message = 'Listing makanan tidak ditemukan.']);

  @override
  String toString() => 'ListingNotFoundFailure($message)';
}

final class InsufficientStockFailure extends ListingFailure {
  const new([super.message = 'Stok makanan tidak mencukupi.']);

  @override
  String toString() => 'InsufficientStockFailure($message)';
}

final class ListingExpiredFailure extends ListingFailure {
  const new([
    super.message = 'Batas waktu pengambilan makanan telah berakhir.',
  ]);

  @override
  String toString() => 'ListingExpiredFailure($message)';
}

final class ListingQuotaExceededFailure extends ListingFailure {
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
    return other is ListingQuotaExceededFailure &&
        other.remaining == remaining &&
        other.dailyLimit == dailyLimit;
  }

  @override
  int get hashCode => Object.hash(runtimeType, remaining, dailyLimit);

  @override
  String toString() =>
      'ListingQuotaExceededFailure(remaining: $remaining, limit: $dailyLimit)';
}

final class InvalidChannelTransitionFailure extends ListingFailure {
  const new([super.message = 'Listing tidak dapat dialihkan ke mode donasi.']);

  @override
  String toString() => 'InvalidChannelTransitionFailure($message)';
}

final class ListingUnknownFailure extends ListingFailure {
  const new([super.message = 'Terjadi kesalahan saat memproses listing.']);

  @override
  String toString() => 'ListingUnknownFailure($message)';
}
