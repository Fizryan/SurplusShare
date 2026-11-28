import 'package:flutter/foundation.dart';

@immutable
sealed class ImpactFailure {
  const new(this.message);

  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other.runtimeType == runtimeType &&
        other is ImpactFailure &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => 'ImpactFailure($message)';
}

final class ImpactPermissionDeniedFailure extends ImpactFailure {
  const new([
    super.message =
        'Hanya mitra terverifikasi atau admin yang dapat '
        'mengunduh laporan CSR/ESG.',
  ]);
}

final class ImpactValidationFailure extends ImpactFailure {
  const new(super.message);
}

final class ImpactExportFailure extends ImpactFailure {
  const new([super.message = 'Gagal membuat dokumen PDF laporan CSR.']);
}
