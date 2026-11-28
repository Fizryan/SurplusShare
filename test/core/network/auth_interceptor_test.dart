import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/network/auth_interceptor.dart';

import '../../helpers/in_memory_token_storage.dart';

class _RecordingRequestHandler extends RequestInterceptorHandler {
  RequestOptions? forwarded;

  @override
  void next(RequestOptions requestOptions) {
    forwarded = requestOptions;
  }
}

class _RecordingErrorHandler extends ErrorInterceptorHandler {
  DioException? forwarded;

  @override
  void next(DioException err) {
    forwarded = err;
  }
}

void main() {
  group('AuthInterceptor (Single Session Token)', () {
    test('injects Bearer header when session token exists', () async {
      final tokenStorage = InMemoryTokenStorage();
      await tokenStorage.saveTokens(
        const AuthTokens(accessToken: 'session-jwt-123'),
      );

      final interceptor = AuthInterceptor(tokenStorage: tokenStorage);
      final options = RequestOptions(path: '/listings');
      final handler = _RecordingRequestHandler();

      await interceptor.onRequest(options, handler);

      expect(handler.forwarded, same(options));
      expect(options.headers['Authorization'], 'Bearer session-jwt-123');
    });

    test('skips Authorization header when skip_auth is true', () async {
      final tokenStorage = InMemoryTokenStorage();
      await tokenStorage.saveTokens(
        const AuthTokens(accessToken: 'session-jwt-123'),
      );

      final interceptor = AuthInterceptor(tokenStorage: tokenStorage);
      final options = RequestOptions(
        path: '/auth/google',
        extra: const {AuthInterceptor.skipAuthKey: true},
      );
      final handler = _RecordingRequestHandler();

      await interceptor.onRequest(options, handler);

      expect(handler.forwarded, same(options));
      expect(options.headers['Authorization'], isNull);
    });

    test('clears token and notifies onSessionExpired on 401', () async {
      final tokenStorage = InMemoryTokenStorage();
      await tokenStorage.saveTokens(
        const AuthTokens(accessToken: 'expired-jwt'),
      );
      var expiredCount = 0;

      final interceptor = AuthInterceptor(
        tokenStorage: tokenStorage,
        onSessionExpired: () => expiredCount++,
      );
      final options = RequestOptions(path: '/listings');
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(requestOptions: options, statusCode: 401),
        type: DioExceptionType.badResponse,
      );
      final handler = _RecordingErrorHandler();

      await interceptor.onError(err, handler);

      expect(handler.forwarded, same(err));
      expect(expiredCount, 1);
      expect(await tokenStorage.getTokens(), isNull);
    });

    test('does not clear session on non-401 or skip_auth 401', () async {
      final tokenStorage = InMemoryTokenStorage();
      await tokenStorage.saveTokens(const AuthTokens(accessToken: 'valid-jwt'));
      var expiredCount = 0;

      final interceptor = AuthInterceptor(
        tokenStorage: tokenStorage,
        onSessionExpired: () => expiredCount++,
      );

      final options500 = RequestOptions(path: '/listings');
      final handler500 = _RecordingErrorHandler();
      await interceptor.onError(
        DioException(
          requestOptions: options500,
          response: Response<dynamic>(
            requestOptions: options500,
            statusCode: 500,
          ),
          type: DioExceptionType.badResponse,
        ),
        handler500,
      );

      final optionsSkip = RequestOptions(
        path: '/auth/google',
        extra: const {AuthInterceptor.skipAuthKey: true},
      );
      final handlerSkip = _RecordingErrorHandler();
      await interceptor.onError(
        DioException(
          requestOptions: optionsSkip,
          response: Response<dynamic>(
            requestOptions: optionsSkip,
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
        handlerSkip,
      );

      expect(handler500.forwarded, isNotNull);
      expect(handlerSkip.forwarded, isNotNull);
      expect(expiredCount, 0);
      expect(await tokenStorage.getAccessToken(), 'valid-jwt');
    });
  });
}
