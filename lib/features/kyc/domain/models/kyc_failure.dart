import 'package:flutter/foundation.dart';

@immutable
sealed class KycFailure {
  const new(this.message);

  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other.runtimeType == runtimeType &&
        other is KycFailure &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => 'KycFailure($message)';
}

final class KycValidationFailure extends KycFailure {
  const new(super.message);

  @override
  String toString() => 'KycValidationFailure($message)';
}

final class KycPermissionDeniedFailure extends KycFailure {
  const new([super.message = 'Anda tidak memiliki izin untuk aksi KYC ini.']);

  @override
  String toString() => 'KycPermissionDeniedFailure($message)';
}

final class KycAlreadySubmittedFailure extends KycFailure {
  const new([
    super.message = 'Pengajuan verifikasi sudah aktif atau telah disetujui.',
  ]);

  @override
  String toString() => 'KycAlreadySubmittedFailure($message)';
}

final class KycNotFoundFailure extends KycFailure {
  const new([super.message = 'Data pengajuan KYC tidak ditemukan.']);

  @override
  String toString() => 'KycNotFoundFailure($message)';
}

final class KycInvalidStatusTransitionFailure extends KycFailure {
  const new([super.message = 'Status pengajuan KYC tidak dapat diubah.']);

  @override
  String toString() => 'KycInvalidStatusTransitionFailure($message)';
}

final class DailyQuotaExceededFailure extends KycFailure {
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
    return other is DailyQuotaExceededFailure &&
        other.remaining == remaining &&
        other.dailyLimit == dailyLimit;
  }

  @override
  int get hashCode => Object.hash(runtimeType, remaining, dailyLimit);

  @override
  String toString() =>
      'DailyQuotaExceededFailure(remaining: $remaining, limit: $dailyLimit)';
}
