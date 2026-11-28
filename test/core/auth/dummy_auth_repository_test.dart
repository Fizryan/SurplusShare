import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/jwt_claims.dart';
import 'package:surplus_share/core/permission/app_role.dart';

import '../../helpers/in_memory_token_storage.dart';

void main() {
  late InMemoryTokenStorage storage;
  late DummyAuthRepository repository;

  setUp(() {
    storage = InMemoryTokenStorage();
    repository = DummyAuthRepository(tokenStorage: storage);
  });

  group('DummyAuthRepository (Google Demo Accounts)', () {
    test('provides exactly one dummy account for every AppRole', () {
      expect(DummyAuthAccounts.all.length, AppRole.values.length);
      expect(
        DummyAuthAccounts.all.map((a) => a.role).toSet(),
        equals(AppRole.values.toSet()),
      );
    });

    test(
      'signInWithGoogle issues valid JWT with name, email, role, and kycStatus',
      () async {
        for (final account in DummyAuthAccounts.all) {
          final result = await repository.signInWithGoogle(
            debugAccountId: account.id,
          );

          expect(result.isRight(), isTrue);
          final tokens = result.getOrElse(
            (_) => throw StateError('unexpected'),
          );
          final claims = JwtClaims.tryParse(tokens.accessToken);

          expect(claims, isNotNull);
          expect(claims!.subject, account.id);
          expect(claims.displayName, account.displayName);
          expect(claims.email, account.email);
          expect(claims.role, account.role);
          expect(claims.kycStatus, account.kycStatus);
          expect(claims.isExpired, isFalse);
          expect(await storage.getTokens(), tokens);
        }
      },
    );

    test(
      'signInWithGoogle returns UnauthorizedFailure for unknown debug ID',
      () async {
        final result = await repository.signInWithGoogle(
          debugAccountId: 'unknown-id',
        );

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<UnauthorizedFailure>()),
          (_) => fail('Expected Left'),
        );
      },
    );

    test('logout clears token storage cleanly', () async {
      await repository.signInWithGoogle(
        debugAccountId: DummyAuthAccounts.donorPartner.id,
      );

      final logoutResult = await repository.logout();
      expect(logoutResult.isRight(), isTrue);
      expect(await storage.getTokens(), isNull);
    });
  });
}
