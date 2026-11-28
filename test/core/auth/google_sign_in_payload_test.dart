import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/auth/google/google_auth_client.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/repository/auth_repository.dart';
import 'package:surplus_share/core/network/api_endpoints.dart';

import '../../helpers/in_memory_token_storage.dart';

class _MockGoogleSignIn extends Mock implements GoogleSignIn;

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount;

class _MockDio extends Mock implements Dio;

void main() {
  group('GoogleSignInClient — payload returned by Google Sign-In v7', () {
    test('returns idToken, googleId, email, displayName, photoUrl (no refresh '
        'token) and forwards exact payload to POST /auth/google', () async {
      final mockGoogleSignIn = _MockGoogleSignIn();
      final mockAccount = _MockGoogleSignInAccount();
      final mockDio = _MockDio();
      final tokenStorage = InMemoryTokenStorage();

      when(
        () => mockGoogleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
      ).thenAnswer((_) async {});
      when(mockGoogleSignIn.supportsAuthenticate).thenReturn(true);
      when(mockGoogleSignIn.authenticate).thenAnswer((_) async => mockAccount);
      when(() => mockAccount.id).thenReturn('google-sub-123456789');
      when(() => mockAccount.email).thenReturn('hafiz@gmail.com');
      when(() => mockAccount.displayName).thenReturn('Hafiz Ryandin');
      when(() => mockAccount.photoUrl)
          .thenReturn('https://lh3.googleusercontent.com/a/photo.jpg');
      when(() => mockAccount.authentication).thenReturn(
        const GoogleSignInAuthentication(idToken: 'google-oidc-id-token-jwt'),
      );

      final client = GoogleSignInClient(
        serverClientId: 'web-client-id.apps.googleusercontent.com',
        googleSignIn: mockGoogleSignIn,
      );

      // 1. Inspect exact credential returned by Google Sign-In.
      final credential = await client.signIn();
      expect(credential.idToken, equals('google-oidc-id-token-jwt'));
      expect(credential.googleId, equals('google-sub-123456789'));
      expect(credential.email, equals('hafiz@gmail.com'));
      expect(credential.displayName, equals('Hafiz Ryandin'));
      expect(
        credential.photoUrl,
        equals('https://lh3.googleusercontent.com/a/photo.jpg'),
      );

      // 2. Verify AuthRepositoryImpl exchanges Google payload for a single
      //    session token (no refresh_token required).
      Map<String, dynamic>? sentBody;
      when(
        () => mockDio.post<Map<String, dynamic>>(
          ApiEndpoints.googleAuth,
          data: any(named: 'data'),
        ),
      ).thenAnswer((invocation) async {
        sentBody = invocation.namedArguments[#data] as Map<String, dynamic>?;
        return Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: ApiEndpoints.googleAuth),
          statusCode: 200,
          data: <String, dynamic>{
            'data': <String, dynamic>{
              'session_token': 'backend-session-jwt-token',
            },
          },
        );
      });

      final repo = AuthRepositoryImpl(
        dio: mockDio,
        tokenStorage: tokenStorage,
        googleAuthClient: client,
      );
      final result = await repo.signInWithGoogle();

      expect(result.isRight(), isTrue);
      final tokens = result.getOrElse((_) => throw StateError('unexpected'));
      expect(
        tokens,
        equals(const AuthTokens(accessToken: 'backend-session-jwt-token')),
      );
      expect(
        sentBody,
        equals({
          'id_token': 'google-oidc-id-token-jwt',
          'google_id': 'google-sub-123456789',
          'email': 'hafiz@gmail.com',
          'name': 'Hafiz Ryandin',
          'picture': 'https://lh3.googleusercontent.com/a/photo.jpg',
        }),
      );
      expect(
        await tokenStorage.getAccessToken(),
        equals('backend-session-jwt-token'),
      );
    });

    test('maps Google cancellation to AuthCancelledFailure', () async {
      final mockGoogleSignIn = _MockGoogleSignIn();
      final mockDio = _MockDio();
      final tokenStorage = InMemoryTokenStorage();

      when(
        () => mockGoogleSignIn.initialize(
          clientId: any(named: 'clientId'),
          serverClientId: any(named: 'serverClientId'),
        ),
      ).thenAnswer((_) async {});
      when(mockGoogleSignIn.supportsAuthenticate).thenReturn(true);
      when(mockGoogleSignIn.authenticate).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'User canceled sign in',
        ),
      );

      final repo = AuthRepositoryImpl(
        dio: mockDio,
        tokenStorage: tokenStorage,
        googleAuthClient: GoogleSignInClient(googleSignIn: mockGoogleSignIn),
      );
      final result = await repo.signInWithGoogle();

      expect(result.isLeft(), isTrue);
      expect(
        result.swap().getOrElse((_) => throw StateError('unexpected')),
        isA<AuthCancelledFailure>(),
      );
    });
  });
}
