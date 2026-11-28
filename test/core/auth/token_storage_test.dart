import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage;

void main() {
  late _MockFlutterSecureStorage secureStorage;
  late SecureTokenStorage tokenStorage;

  setUp(() {
    secureStorage = _MockFlutterSecureStorage();
    tokenStorage = SecureTokenStorage(secureStorage);
  });

  group('SecureTokenStorage', () {
    test('saveTokens writes session token', () async {
      when(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      const tokens = AuthTokens(accessToken: 'access-1');
      await tokenStorage.saveTokens(tokens);

      verify(
        () => secureStorage.write(
          key: SecureTokenStorage.accessTokenKey,
          value: 'access-1',
        ),
      ).called(1);
    });

    test('getTokens returns AuthTokens when stored', () async {
      when(() => secureStorage.read(key: SecureTokenStorage.accessTokenKey))
          .thenAnswer((_) async => 'access-1');

      final result = await tokenStorage.getTokens();

      expect(result, const AuthTokens(accessToken: 'access-1'));
    });

    test('getTokens returns null when token is missing or blank', () async {
      when(() => secureStorage.read(key: SecureTokenStorage.accessTokenKey))
          .thenAnswer((_) async => '   ');

      final result = await tokenStorage.getTokens();

      expect(result, isNull);
    });

    test('clearTokens deletes access token and legacy refresh key', () async {
      when(() => secureStorage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      await tokenStorage.clearTokens();

      verify(() => secureStorage.delete(key: SecureTokenStorage.accessTokenKey))
          .called(1);
      verify(() => secureStorage.delete(key: 'auth_refresh_token')).called(1);
    });

    test(
      'caches token in memory to avoid repeated platform channel reads',
      () async {
        when(
          () => secureStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});

        await tokenStorage.saveTokens(
          const AuthTokens(accessToken: 'cached-a'),
        );

        expect(await tokenStorage.getAccessToken(), 'cached-a');
        expect(
          await tokenStorage.getTokens(),
          const AuthTokens(accessToken: 'cached-a'),
        );

        verifyNever(() => secureStorage.read(key: any(named: 'key')));
      },
    );

    test('propagates PlatformException on storage error', () async {
      when(() => secureStorage.read(key: SecureTokenStorage.accessTokenKey))
          .thenThrow(PlatformException(code: 'STORAGE_ERROR'));

      expect(
        () => tokenStorage.getAccessToken(),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
