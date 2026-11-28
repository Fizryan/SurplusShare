import 'package:flutter/foundation.dart';

@immutable
sealed class AuthFailure {
  const new(this.message);

  final String message;

  bool get isRetryable => false;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other.runtimeType == runtimeType &&
        other is AuthFailure &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => 'AuthFailure($message)';
}

final class NetworkFailure extends AuthFailure {
  const new([super.message = 'Koneksi jaringan bermasalah.']);

  @override
  bool get isRetryable => true;

  @override
  String toString() => 'NetworkFailure($message)';
}

final class UnauthorizedFailure extends AuthFailure {
  const new([super.message = 'Sesi tidak valid atau telah berakhir.']);

  @override
  String toString() => 'UnauthorizedFailure($message)';
}

final class ServerFailure extends AuthFailure {
  const new(super.message, {this.statusCode});

  final int? statusCode;

  @override
  bool get isRetryable => statusCode != null && statusCode! >= 500;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerFailure &&
        other.message == message &&
        other.statusCode == statusCode;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, statusCode);

  @override
  String toString() => 'ServerFailure(statusCode: $statusCode, $message)';
}

final class StorageFailure extends AuthFailure {
  const new([super.message = 'Gagal mengakses penyimpanan aman.']);

  @override
  String toString() => 'StorageFailure($message)';
}

final class AuthCancelledFailure extends AuthFailure {
  const new([super.message = 'Masuk dengan Google dibatalkan.']);

  @override
  String toString() => 'AuthCancelledFailure($message)';
}

final class UnknownFailure extends AuthFailure {
  const new([super.message = 'Terjadi kesalahan tidak terduga.']);

  @override
  String toString() => 'UnknownFailure($message)';
}
