import 'dart:async';

import 'package:dio/dio.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/models/jwt_claims.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';

typedef TokenRefreshCallback = Future<AuthTokens?> Function(
  String refreshToken,
);
typedef TokensRefreshedCallback = FutureOr<void> Function(AuthTokens tokens);
typedef SessionExpiredCallback = FutureOr<void> Function();
typedef RetryRequestCallback = Future<Response<dynamic>> Function(
  RequestOptions options,
);

class AuthInterceptor extends Interceptor {
  new({
    required this._tokenStorage,
    required this._onRefresh,
    required this._retryRequest,
    this._onTokensRefreshed,
    this._onSessionExpired,
    this._proactiveRefreshBuffer = const Duration(seconds: 30),
  });

  static const skipAuthKey = 'skip_auth';
  static const retriedKey = 'auth_retried';
  static const _authHeader = 'Authorization';
  static const _bearerPrefix = 'Bearer ';

  final TokenStorage _tokenStorage;
  final TokenRefreshCallback _onRefresh;
  final RetryRequestCallback _retryRequest;
  final TokensRefreshedCallback? _onTokensRefreshed;
  final SessionExpiredCallback? _onSessionExpired;
  final Duration _proactiveRefreshBuffer;

  Future<AuthTokens?>? _refreshFuture;

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
      var accessToken = await _tokenStorage.getAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        final claims = JwtClaims.tryParse(accessToken);
        if (claims != null &&
            claims.isExpiringSoon(buffer: _proactiveRefreshBuffer)) {
          final refreshed = await _resolveNewAccessToken(accessToken);
          if (refreshed != null && refreshed.isNotEmpty) {
            accessToken = refreshed;
          }
        }
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
    if (!_shouldAttemptRefresh(err)) {
      handler.next(err);
      return;
    }

    final failedToken = _extractBearerToken(err.requestOptions.headers);
    final newAccessToken = await _resolveNewAccessToken(failedToken);

    if (newAccessToken == null || newAccessToken.isEmpty) {
      handler.next(err);
      return;
    }

    final retryOptions = err.requestOptions.copyWith(
      headers: <String, dynamic>{
        ...err.requestOptions.headers,
        _authHeader: '$_bearerPrefix$newAccessToken',
      },
      extra: <String, dynamic>{...err.requestOptions.extra, retriedKey: true},
    );

    try {
      final response = await _retryRequest(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _shouldAttemptRefresh(DioException err) {
    if (err.response?.statusCode != 401) return false;
    if (err.requestOptions.extra[skipAuthKey] == true) return false;
    if (err.requestOptions.extra[retriedKey] == true) return false;
    return true;
  }

  String? _extractBearerToken(Map<String, dynamic> headers) {
    final raw = headers[_authHeader] ?? headers[_authHeader.toLowerCase()];
    if (raw is! String) return null;
    if (raw.startsWith(_bearerPrefix)) {
      return raw.substring(_bearerPrefix.length).trim();
    }
    return raw.trim();
  }

  Future<String?> _resolveNewAccessToken(String? failedToken) async {
    final inFlight = _refreshFuture;
    if (inFlight != null) {
      final refreshed = await inFlight;
      return refreshed?.accessToken;
    }

    try {
      final currentToken = await _tokenStorage.getAccessToken();
      if (currentToken != null &&
          currentToken.isNotEmpty &&
          currentToken != failedToken) {
        return currentToken;
      }
    } on Object {
      // Fall through to refresh attempt.
    }

    // Re-check after async storage read to guarantee single-flight refresh.
    final racedInFlight = _refreshFuture;
    if (racedInFlight != null) {
      final refreshed = await racedInFlight;
      return refreshed?.accessToken;
    }

    final refreshFuture = _executeRefresh();
    _refreshFuture = refreshFuture;
    try {
      final refreshed = await refreshFuture;
      return refreshed?.accessToken;
    } finally {
      if (identical(_refreshFuture, refreshFuture)) {
        _refreshFuture = null;
      }
    }
  }

  Future<AuthTokens?> _executeRefresh() async {
    String? refreshToken;
    try {
      refreshToken = await _tokenStorage.getRefreshToken();
    } on Object {
      return null;
    }

    if (refreshToken == null || refreshToken.isEmpty) {
      await _expireSession();
      return null;
    }

    try {
      final newTokens = await _onRefresh(refreshToken);
      if (newTokens == null) {
        await _expireSession();
        return null;
      }

      await _tokenStorage.saveTokens(newTokens);
      await _onTokensRefreshed?.call(newTokens);
      return newTokens;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        await _expireSession();
      }
      return null;
    } on FormatException {
      await _expireSession();
      return null;
    } on Object {
      return null;
    }
  }

  Future<void> _expireSession() async {
    try {
      await _tokenStorage.clearTokens();
    } on Object {
      // Still notify session expiration even if storage clear fails.
    }
    await _onSessionExpired?.call();
  }
}
