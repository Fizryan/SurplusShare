import 'package:dio/dio.dart';
import 'package:surplus_share/core/network/auth_interceptor.dart';

abstract final class AuthRequestOptions {
  /// Returns Dio [Options] that bypass `AuthInterceptor` token attachment
  /// and 401 refresh handling (for public endpoints).
  static Options public({
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
  }) {
    return Options(
      headers: headers,
      extra: <String, dynamic>{...?extra, AuthInterceptor.skipAuthKey: true},
    );
  }
}
