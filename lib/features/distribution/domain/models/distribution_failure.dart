import 'package:flutter/foundation.dart';

@immutable
sealed class DistributionFailure {
  const new(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType &&
          other is DistributionFailure &&
          other.message == message);

  @override
  int get hashCode => Object.hash(runtimeType, message);
}

final class DistributionValidationFailure extends DistributionFailure {
  const new(super.message);
}

final class DistributionPermissionDeniedFailure extends DistributionFailure {
  const new([
    super.message = 'Anda tidak memiliki izin untuk aksi distribusi ini.',
  ]);
}

final class DistributionNotFoundFailure extends DistributionFailure {
  const new([super.message = 'Tugas distribusi tidak ditemukan.']);
}

final class InvalidDistributionTransitionFailure extends DistributionFailure {
  const new(super.message);
}

final class InvalidDistributionPinFailure extends DistributionFailure {
  const new({required this.remainingAttempts, String? message})
    : super(
        message ?? 'PIN tidak sesuai. Sisa percobaan: $remainingAttempts kali.',
      );

  final int remainingAttempts;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is InvalidDistributionPinFailure &&
      other.remainingAttempts == remainingAttempts;

  @override
  int get hashCode => Object.hash(super.hashCode, remainingAttempts);
}

final class DistributionPinLockedFailure extends DistributionFailure {
  const new([
    super.message =
        'Verifikasi PIN terkunci setelah terlalu banyak percobaan salah.',
  ]);
}
