import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/network/auth_interceptor.dart';

class _InMemoryTokenStorage implements TokenStorage {
  new({this.readDelay = Duration.zero});

  final Duration readDelay;
  AuthTokens? _tokens;
  int clearCount = 0;

  @override
  Future<void> clearTokens() async {
    clearCount++;
    _tokens = null;
  }

  @override
  Future<String?> getAccessToken() async {
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    return _tokens?.accessToken;
  }

  @override
  Future<String?> getRefreshToken() async {
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    return _tokens?.refreshToken;
  }

  @override
  Future<AuthTokens?> getTokens() async => _tokens;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _tokens = tokens;
  }
}

typedef _AdapterHandler = Future<ResponseBody> Function(RequestOptions options);

class _FakeHttpClientAdapter implements HttpClientAdapter {
  new(this._handler);

  final _AdapterHandler _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late _InMemoryTokenStorage tokenStorage;
  late Dio dio;

  setUp(() {
    tokenStorage = _InMemoryTokenStorage();
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
  });

  group('AuthInterceptor', () {
    test('attaches Bearer accessToken to requests', () async {
      await tokenStorage.saveTokens(
        const AuthTokens(accessToken: 'token-v1', refreshToken: 'refresh-v1'),
      );

      String? capturedAuthHeader;
      dio
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          capturedAuthHeader = options.headers['Authorization'] as String?;
          return _jsonBody({'ok': true}, 200);
        })
        ..interceptors.add(
          AuthInterceptor(
            tokenStorage: tokenStorage,
            retryRequest: dio.fetch,
            onRefresh: (_) async => null,
          ),
        );

      final response = await dio.get<Map<String, dynamic>>('/listings');

      expect(response.statusCode, 200);
      expect(capturedAuthHeader, 'Bearer token-v1');
    });

    test('skips Authorization header when extra skip_auth is true', () async {
      await tokenStorage.saveTokens(
        const AuthTokens(accessToken: 'token-v1', refreshToken: 'refresh-v1'),
      );

      Object? capturedAuthHeader;
      dio
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          capturedAuthHeader = options.headers['Authorization'];
          return _jsonBody({'ok': true}, 200);
        })
        ..interceptors.add(
          AuthInterceptor(
            tokenStorage: tokenStorage,
            retryRequest: dio.fetch,
            onRefresh: (_) async => null,
          ),
        );

      await dio.get<Map<String, dynamic>>(
        '/public',
        options: Options(extra: const {AuthInterceptor.skipAuthKey: true}),
      );

      expect(capturedAuthHeader, isNull);
    });

    test('refreshes token once and retries request on 401', () async {
      await tokenStorage.saveTokens(
        const AuthTokens(accessToken: 'expired-token', refreshToken: 'ref-1'),
      );

      var refreshCalls = 0;
      AuthTokens? syncedTokens;

      dio
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.headers['Authorization'] == 'Bearer expired-token') {
            return _jsonBody({'message': 'expired'}, 401);
          }
          if (options.headers['Authorization'] == 'Bearer fresh-token') {
            return _jsonBody({'data': 'secret'}, 200);
          }
          return _jsonBody({'message': 'unexpected'}, 400);
        })
        ..interceptors.add(
          AuthInterceptor(
            tokenStorage: tokenStorage,
            retryRequest: dio.fetch,
            onRefresh: (refreshToken) async {
              refreshCalls++;
              expect(refreshToken, 'ref-1');
              return const AuthTokens(
                accessToken: 'fresh-token',
                refreshToken: 'ref-2',
              );
            },
            onTokensRefreshed: (tokens) => syncedTokens = tokens,
          ),
        );

      final response = await dio.get<Map<String, dynamic>>('/protected');

      expect(response.statusCode, 200);
      expect(response.data, {'data': 'secret'});
      expect(refreshCalls, 1);
      expect(
        await tokenStorage.getTokens(),
        const AuthTokens(accessToken: 'fresh-token', refreshToken: 'ref-2'),
      );
      expect(
        syncedTokens,
        const AuthTokens(accessToken: 'fresh-token', refreshToken: 'ref-2'),
      );
    });

    test(
      'concurrent 401 requests trigger only a single refresh call',
      () async {
        await tokenStorage.saveTokens(
          const AuthTokens(accessToken: 'expired-token', refreshToken: 'ref-1'),
        );

        var refreshCalls = 0;

        dio
          ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
            if (options.headers['Authorization'] == 'Bearer expired-token') {
              return _jsonBody({'message': 'expired'}, 401);
            }
            if (options.headers['Authorization'] == 'Bearer fresh-token') {
              return _jsonBody({'path': options.path}, 200);
            }
            return _jsonBody({'message': 'bad'}, 400);
          })
          ..interceptors.add(
            AuthInterceptor(
              tokenStorage: tokenStorage,
              retryRequest: dio.fetch,
              onRefresh: (_) async {
                refreshCalls++;
                await Future<void>.delayed(const Duration(milliseconds: 30));
                return const AuthTokens(
                  accessToken: 'fresh-token',
                  refreshToken: 'ref-2',
                );
              },
            ),
          );

        final responses = await Future.wait([
          dio.get<Map<String, dynamic>>('/a'),
          dio.get<Map<String, dynamic>>('/b'),
          dio.get<Map<String, dynamic>>('/c'),
          dio.get<Map<String, dynamic>>('/d'),
        ]);

        expect(refreshCalls, 1);
        expect(responses.map((r) => r.statusCode), everyElement(200));
        expect(
          responses.map((r) => r.data?['path']),
          equals(['/a', '/b', '/c', '/d']),
        );
      },
    );

    test(
      'prevents infinite retry loop when retried request still returns 401',
      () async {
        await tokenStorage.saveTokens(
          const AuthTokens(accessToken: 'old-token', refreshToken: 'ref-1'),
        );

        var refreshCalls = 0;
        var requestAttempts = 0;

        dio
          ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
            requestAttempts++;
            return _jsonBody({'message': 'still unauthorized'}, 401);
          })
          ..interceptors.add(
            AuthInterceptor(
              tokenStorage: tokenStorage,
              retryRequest: dio.fetch,
              onRefresh: (_) async {
                refreshCalls++;
                return const AuthTokens(
                  accessToken: 'new-token',
                  refreshToken: 'ref-2',
                );
              },
            ),
          );

        await expectLater(
          () => dio.get<Map<String, dynamic>>('/always-401'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'statusCode',
              401,
            ),
          ),
        );

        expect(refreshCalls, 1);
        expect(requestAttempts, 2);
      },
    );

    test(
      'clears tokens and invokes onSessionExpired when refresh fails 401',
      () async {
        await tokenStorage.saveTokens(
          const AuthTokens(
            accessToken: 'old-token',
            refreshToken: 'revoked-ref',
          ),
        );

        var sessionExpiredCalled = 0;

        dio
          ..httpClientAdapter = _FakeHttpClientAdapter(
            (_) async => _jsonBody({'message': 'unauthorized'}, 401),
          )
          ..interceptors.add(
            AuthInterceptor(
              tokenStorage: tokenStorage,
              retryRequest: dio.fetch,
              onRefresh: (_) async {
                throw DioException(
                  requestOptions: RequestOptions(path: '/auth/refresh'),
                  response: Response<dynamic>(
                    requestOptions: RequestOptions(path: '/auth/refresh'),
                    statusCode: 401,
                  ),
                  type: DioExceptionType.badResponse,
                );
              },
              onSessionExpired: () => sessionExpiredCalled++,
            ),
          );

        await expectLater(
          () => dio.get<Map<String, dynamic>>('/protected'),
          throwsA(isA<DioException>()),
        );

        expect(sessionExpiredCalled, 1);
        expect(tokenStorage.clearCount, 1);
        expect(await tokenStorage.getTokens(), isNull);
      },
    );

    test(
      'does not clear tokens on transient network error during refresh',
      () async {
        await tokenStorage.saveTokens(
          const AuthTokens(accessToken: 'old-token', refreshToken: 'valid-ref'),
        );

        var sessionExpiredCalled = 0;

        dio
          ..httpClientAdapter = _FakeHttpClientAdapter(
            (_) async => _jsonBody({'message': 'unauthorized'}, 401),
          )
          ..interceptors.add(
            AuthInterceptor(
              tokenStorage: tokenStorage,
              retryRequest: dio.fetch,
              onRefresh: (_) async {
                throw DioException(
                  requestOptions: RequestOptions(path: '/auth/refresh'),
                  type: DioExceptionType.connectionTimeout,
                );
              },
              onSessionExpired: () => sessionExpiredCalled++,
            ),
          );

        await expectLater(
          () => dio.get<Map<String, dynamic>>('/protected'),
          throwsA(isA<DioException>()),
        );

        expect(sessionExpiredCalled, 0);
        expect(tokenStorage.clearCount, 0);
        expect(await tokenStorage.getRefreshToken(), 'valid-ref');
      },
    );

    test('passes through non-401 errors without refreshing', () async {
      await tokenStorage.saveTokens(
        const AuthTokens(accessToken: 'token-v1', refreshToken: 'ref-1'),
      );

      var refreshCalls = 0;

      dio
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) async => _jsonBody({'message': 'server error'}, 500),
        )
        ..interceptors.add(
          AuthInterceptor(
            tokenStorage: tokenStorage,
            retryRequest: dio.fetch,
            onRefresh: (_) async {
              refreshCalls++;
              return null;
            },
          ),
        );

      await expectLater(
        () => dio.get<Map<String, dynamic>>('/broken'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            500,
          ),
        ),
      );

      expect(refreshCalls, 0);
    });

    test(
      'concurrent 401 with slow async storage still refreshes only once',
      () async {
        final slowStorage = _InMemoryTokenStorage(
          readDelay: const Duration(milliseconds: 20),
        );
        await slowStorage.saveTokens(
          const AuthTokens(accessToken: 'expired-token', refreshToken: 'ref-1'),
        );

        var refreshCalls = 0;
        final localDio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
        localDio
          ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
            if (options.headers['Authorization'] == 'Bearer expired-token') {
              return _jsonBody({'message': 'expired'}, 401);
            }
            if (options.headers['Authorization'] == 'Bearer fresh-token') {
              return _jsonBody({'ok': true}, 200);
            }
            return _jsonBody({'message': 'bad'}, 400);
          })
          ..interceptors.add(
            AuthInterceptor(
              tokenStorage: slowStorage,
              retryRequest: localDio.fetch,
              onRefresh: (_) async {
                refreshCalls++;
                await Future<void>.delayed(const Duration(milliseconds: 20));
                return const AuthTokens(
                  accessToken: 'fresh-token',
                  refreshToken: 'ref-2',
                );
              },
            ),
          );

        final responses = await Future.wait([
          localDio.get<Map<String, dynamic>>('/1'),
          localDio.get<Map<String, dynamic>>('/2'),
          localDio.get<Map<String, dynamic>>('/3'),
        ]);

        expect(refreshCalls, 1);
        expect(responses.map((r) => r.statusCode), everyElement(200));
      },
    );

    test('proactively refreshes expiring JWT before sending request', () async {
      final header = base64Url.encode(
        utf8.encode(jsonEncode({'alg': 'HS256'})),
      );
      final expSeconds =
          DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 10))
              .millisecondsSinceEpoch ~/
          1000;
      final body = base64Url.encode(
        utf8.encode(jsonEncode({'sub': 'u1', 'exp': expSeconds})),
      );
      final expiringJwt = '$header.$body.sig';

      await tokenStorage.saveTokens(
        AuthTokens(accessToken: expiringJwt, refreshToken: 'ref-1'),
      );

      var refreshCalls = 0;
      String? sentHeader;

      dio
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          sentHeader = options.headers['Authorization'] as String?;
          return _jsonBody({'ok': true}, 200);
        })
        ..interceptors.add(
          AuthInterceptor(
            tokenStorage: tokenStorage,
            retryRequest: dio.fetch,
            onRefresh: (_) async {
              refreshCalls++;
              return const AuthTokens(
                accessToken: 'proactive-fresh-token',
                refreshToken: 'ref-2',
              );
            },
          ),
        );

      final response = await dio.get<Map<String, dynamic>>('/profile');

      expect(response.statusCode, 200);
      expect(refreshCalls, 1);
      expect(sentHeader, 'Bearer proactive-fresh-token');
    });
  });
}
