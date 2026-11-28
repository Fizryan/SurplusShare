import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/auth/google/google_auth_client.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/repository/auth_repository.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';

class _MockDio extends Mock implements Dio;

class _MockTokenStorage extends Mock implements TokenStorage;

class _MockGoogleAuthClient extends Mock implements GoogleAuthClient;

void main() {
  late _MockDio dio;
  late _MockTokenStorage tokenStorage;
  late _MockGoogleAuthClient googleAuthClient;
  late AuthRepositoryImpl repository;

  const sampleCredential = GoogleAuthCredential(
    idToken: 'google-id-token-123',
    email: 'budi@gmail.com',
    displayName: 'Budi',
    photoUrl: 'https://example.com/photo.jpg',
  );

  setUpAll(() {
    registerFallbackValue(
      const AuthTokens(accessToken: 'fallback', refreshToken: 'fallback'),
    );
  });

  setUp(() {
    dio = _MockDio();
    tokenStorage = _MockTokenStorage();
    googleAuthClient = _MockGoogleAuthClient();
    repository = AuthRepositoryImpl(
      dio: dio,
      tokenStorage: tokenStorage,
      googleAuthClient: googleAuthClient,
    );
  });

  group('AuthRepositoryImpl (Google Auth)', () {
    test(
      'signInWithGoogle exchanges Google idToken and saves JWT tokens',
      () async {
        when(() => googleAuthClient.signIn())
            .thenAnswer((_) async => sampleCredential);
        when(
          () => dio.post<Map<String, dynamic>>(
            ApiEndpoints.googleAuth,
            data: {
              'id_token': 'google-id-token-123',
              'email': 'budi@gmail.com',
              'name': 'Budi',
              'picture': 'https://example.com/photo.jpg',
            },
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: ApiEndpoints.googleAuth),
            statusCode: 200,
            data: {
              'data': {'access_token': 'acc-1', 'refresh_token': 'ref-1'},
            },
          ),
        );
        when(() => tokenStorage.saveTokens(any())).thenAnswer((_) async {});

        final result = await repository.signInWithGoogle();

        expect(
          result,
          right<AuthFailure, AuthTokens>(
            const AuthTokens(accessToken: 'acc-1', refreshToken: 'ref-1'),
          ),
        );
        verify(
          () => tokenStorage.saveTokens(
            const AuthTokens(accessToken: 'acc-1', refreshToken: 'ref-1'),
          ),
        ).called(1);
      },
    );

    test(
      'signInWithGoogle maps user cancellation to AuthCancelledFailure',
      () async {
        when(() => googleAuthClient.signIn())
            .thenThrow(const GoogleAuthCancelledException());

        final result = await repository.signInWithGoogle();

        expect(
          result,
          left<AuthFailure, AuthTokens>(const AuthCancelledFailure()),
        );
        verifyNever(
          () => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
        );
        verifyNever(() => tokenStorage.saveTokens(any()));
      },
    );

    test(
      'signInWithGoogle maps 401 DioException to UnauthorizedFailure',
      () async {
        when(() => googleAuthClient.signIn())
            .thenAnswer((_) async => sampleCredential);
        when(
          () => dio.post<Map<String, dynamic>>(
            ApiEndpoints.googleAuth,
            data: any(named: 'data'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: ApiEndpoints.googleAuth),
            response: Response<Map<String, dynamic>>(
              requestOptions: RequestOptions(path: ApiEndpoints.googleAuth),
              statusCode: 401,
              data: {'message': 'Token Google tidak valid'},
            ),
            type: DioExceptionType.badResponse,
          ),
        );

        final result = await repository.signInWithGoogle();

        expect(
          result,
          left<AuthFailure, AuthTokens>(
            const UnauthorizedFailure('Token Google tidak valid'),
          ),
        );
        verifyNever(() => tokenStorage.saveTokens(any()));
      },
    );

    test('signInWithGoogle maps connectionTimeout to NetworkFailure', () async {
      when(() => googleAuthClient.signIn())
          .thenAnswer((_) async => sampleCredential);
      when(
        () => dio.post<Map<String, dynamic>>(
          ApiEndpoints.googleAuth,
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ApiEndpoints.googleAuth),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await repository.signInWithGoogle();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<NetworkFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test(
      'refreshTokens returns UnauthorizedFailure if no stored refreshToken',
      () async {
        when(() => tokenStorage.getRefreshToken())
            .thenAnswer((_) async => null);

        final result = await repository.refreshTokens();

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<UnauthorizedFailure>()),
          (_) => fail('Expected Left'),
        );
      },
    );

    test('refreshTokens clears tokens when server returns 401', () async {
      when(() => tokenStorage.getRefreshToken())
          .thenAnswer((_) async => 'expired-ref');
      when(() => tokenStorage.clearTokens()).thenAnswer((_) async {});
      when(
        () => dio.post<Map<String, dynamic>>(
          ApiEndpoints.refresh,
          data: {'refresh_token': 'expired-ref'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ApiEndpoints.refresh),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: ApiEndpoints.refresh),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await repository.refreshTokens();

      expect(result.isLeft(), isTrue);
      verify(() => tokenStorage.clearTokens()).called(1);
    });

    test(
      'logout signs out Google and clears local tokens even on network fail',
      () async {
        when(() => tokenStorage.getRefreshToken())
            .thenAnswer((_) async => 'ref-1');
        when(
          () => dio.post<dynamic>(
            ApiEndpoints.logout,
            data: {'refresh_token': 'ref-1'},
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: ApiEndpoints.logout),
            type: DioExceptionType.connectionError,
          ),
        );
        when(() => googleAuthClient.signOut()).thenAnswer((_) async {});
        when(() => tokenStorage.clearTokens()).thenAnswer((_) async {});

        final result = await repository.logout();

        expect(result, right<AuthFailure, Unit>(unit));
        verify(() => googleAuthClient.signOut()).called(1);
        verify(() => tokenStorage.clearTokens()).called(1);
      },
    );

    test('restoreSession maps PlatformException to StorageFailure', () async {
      when(
        () => tokenStorage.getTokens(),
      ).thenThrow(PlatformException(code: 'ERR', message: 'Keystore locked'));

      final result = await repository.restoreSession();

      expect(
        result,
        left<AuthFailure, AuthTokens?>(const StorageFailure('Keystore locked')),
      );
    });
  });
}
