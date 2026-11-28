import 'dart:async';

import 'package:dio/dio.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';

typedef SessionExpiredCallback = FutureOr<void> Function();

/// Attaches the stored Bearer session token to outbound requests and expires
/// the local session on `401 Unauthorized` so the user re-authenticates via
/// Google Sign-In.
class AuthInterceptor extends Interceptor {
  const new({required this._tokenStorage, this._onSessionExpired});

  static const skipAuthKey = 'skip_auth';
  static const _authHeader = 'Authorization';
  static const _bearerPrefix = 'Bearer ';

  final TokenStorage _tokenStorage;
  final SessionExpiredCallback? _onSessionExpired;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[skipAuthKey] == true) {
      handler.next(options);
      return;
    }

    try {
      final accessToken = await _tokenStorage.getAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        options.headers[_authHeader] = '$_bearerPrefix$accessToken';
      }
    } on Object {
      // Proceed without Authorization header if storage read fails;
      // server response will handle authorization.
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 &&
        err.requestOptions.extra[skipAuthKey] != true) {
      try {
        await _tokenStorage.clearTokens();
      } on Object {
        // Still notify session expiration even if storage clear fails.
      }
      await _onSessionExpired?.call();
    }

    handler.next(err);
  }
}
