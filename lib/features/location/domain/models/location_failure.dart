import 'package:flutter/foundation.dart';

@immutable
sealed class LocationFailure {
  const new(this.message);

  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other.runtimeType == runtimeType &&
        other is LocationFailure &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => 'LocationFailure($message)';
}

final class LocationServiceDisabledFailure extends LocationFailure {
  const new([
    super.message = 'Layanan lokasi (GPS) tidak aktif. Mohon aktifkan GPS.',
  ]);
}

final class LocationPermissionDeniedFailure extends LocationFailure {
  const new([super.message = 'Izin akses lokasi ditolak.']);
}

final class LocationPermissionDeniedForeverFailure extends LocationFailure {
  const new([
    super.message =
        'Izin akses lokasi ditolak permanen. Aktifkan di '
        'pengaturan perangkat.',
  ]);
}

final class LocationTimeoutFailure extends LocationFailure {
  const new([super.message = 'Gagal mendapatkan posisi GPS (timeout).']);
}

final class LocationUnknownFailure extends LocationFailure {
  const new([super.message = 'Gagal membaca lokasi perangkat.']);
}
