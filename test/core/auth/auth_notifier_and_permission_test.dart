import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_state.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/repository/auth_repository.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';

import '../../helpers/in_memory_token_storage.dart';

class _MockAuthRepository extends Mock implements AuthRepository;

String _buildJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'})));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.sig';
}

void main() {
  late _MockAuthRepository repository;
  late InMemoryTokenStorage tokenStorage;
  late ProviderContainer container;

  setUp(() {
    repository = _MockAuthRepository();
    tokenStorage = InMemoryTokenStorage();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        tokenStorageProvider.overrideWithValue(tokenStorage),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('AuthNotifier & Permission integration', () {
    test('starts in AuthInitial with empty permissions', () {
      expect(container.read(authNotifierProvider), const AuthInitial());
      expect(container.read(currentPermissionProvider), isEmpty);
      expect(container.read(currentUserIdProvider), isNull);
      expect(
        container.read(
          hasPermissionProvider(Permission.browseDiscountListings),
        ),
        isFalse,
      );
    });

    test('signInWithGoogle transitions to AuthAuthenticated and resolves '
        'permissions & claims', () async {
      final jwt = _buildJwt({
        'sub': 'u1',
        'name': 'Budi',
        'email': 'budi@gmail.com',
        'role': 'consumer',
      });
      final tokens = AuthTokens(accessToken: jwt);

      when(() => repository.signInWithGoogle())
          .thenAnswer((_) async => right(tokens));

      final ok = await container
          .read(authNotifierProvider.notifier)
          .signInWithGoogle();

      expect(ok, isTrue);
      expect(container.read(authNotifierProvider), isA<AuthAuthenticated>());
      expect(container.read(currentUserIdProvider), 'u1');
      expect(container.read(currentClaimsProvider)?.displayName, 'Budi');
      expect(
        container.read(currentPermissionProvider),
        equals({Permission.browseDiscountListings}),
      );
      expect(
        container.read(
          hasPermissionProvider(Permission.browseDiscountListings),
        ),
        isTrue,
      );
      expect(
        container.read(
          hasAllPermissionProvider(const {Permission.browseDiscountListings}),
        ),
        isTrue,
      );
    });

    test(
      'revoked permissions in JWT remove default role permissions',
      () async {
        final jwt = _buildJwt({
          'sub': 'u2',
          'role': 'consumer',
          'revoked_permissions': ['browse_discount_listings'],
        });
        final tokens = AuthTokens(accessToken: jwt);

        when(() => repository.signInWithGoogle())
            .thenAnswer((_) async => right(tokens));

        final ok = await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle();

        expect(ok, isTrue);
        expect(container.read(currentPermissionProvider), isEmpty);
        expect(
          container.read(
            hasPermissionProvider(Permission.browseDiscountListings),
          ),
          isFalse,
        );
      },
    );

    test(
      'signInWithGoogle failure sets AuthUnauthenticated with failure',
      () async {
        when(() => repository.signInWithGoogle())
            .thenAnswer((_) async => left(const UnauthorizedFailure('Gagal')));

        final ok = await container
            .read(authNotifierProvider.notifier)
            .signInWithGoogle();

        expect(ok, isFalse);
        expect(
          container.read(authNotifierProvider),
          const AuthUnauthenticated(failure: UnauthorizedFailure('Gagal')),
        );
        expect(container.read(currentPermissionProvider), isEmpty);
      },
    );

    test(
      'restoreSession restores authenticated session when token is valid',
      () async {
        final jwt = _buildJwt({'sub': 'u-restored', 'role': 'consumer'});
        final tokens = AuthTokens(accessToken: jwt);
        when(() => repository.restoreSession())
            .thenAnswer((_) async => right(tokens));

        await container.read(authNotifierProvider.notifier).restoreSession();

        expect(container.read(authNotifierProvider), isA<AuthAuthenticated>());
        expect(
          container.read(currentPermissionProvider),
          equals({Permission.browseDiscountListings}),
        );
      },
    );

    test('logout and expireSession clear permissions', () async {
      final jwt = _buildJwt({'sub': 'u1', 'role': 'consumer'});
      final tokens = AuthTokens(accessToken: jwt);
      when(() => repository.signInWithGoogle())
          .thenAnswer((_) async => right(tokens));

      await container.read(authNotifierProvider.notifier).signInWithGoogle();
      expect(container.read(currentPermissionProvider), isNotEmpty);

      container.read(authNotifierProvider.notifier).expireSession();
      expect(
        container.read(authNotifierProvider),
        const AuthUnauthenticated(failure: UnauthorizedFailure()),
      );
      expect(container.read(currentPermissionProvider), isEmpty);

      when(() => repository.logout()).thenAnswer((_) async => right(unit));
      await container.read(authNotifierProvider.notifier).logout();
      expect(container.read(authNotifierProvider), const AuthUnauthenticated());
    });

    test('restoreSession clears expired session token and logs out', () async {
      final expiredExp =
          DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch ~/
          1000;
      final expiredJwt = _buildJwt({
        'sub': 'u1',
        'role': 'consumer',
        'exp': expiredExp,
      });

      await tokenStorage.saveTokens(AuthTokens(accessToken: expiredJwt));
      when(() => repository.restoreSession())
          .thenAnswer((_) async => right(AuthTokens(accessToken: expiredJwt)));

      await container.read(authNotifierProvider.notifier).restoreSession();

      expect(
        container.read(authNotifierProvider),
        const AuthUnauthenticated(failure: UnauthorizedFailure()),
      );
      expect(await tokenStorage.getTokens(), isNull);
    });
  });
}
