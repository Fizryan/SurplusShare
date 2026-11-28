import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/google/google_auth_client.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_state.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/models/jwt_claims.dart';
import 'package:surplus_share/core/auth/repository/auth_repository.dart';
import 'package:surplus_share/core/auth/storage/token_storage.dart';
import 'package:surplus_share/core/config/api_config.dart';
import 'package:surplus_share/core/network/auth_interceptor.dart';
import 'package:surplus_share/core/network/dio_client.dart';

final apiConfigProvider = Provider<ApiConfig>((ref) {
  return const ApiConfig.fromEnvironment();
});

final flutterSecureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  final storage = ref.watch(flutterSecureStorageProvider);
  return SecureTokenStorage(storage);
});

final googleAuthClientProvider = Provider<GoogleAuthClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  return GoogleSignInClient(
    clientId: config.effectiveGoogleClientId,
    serverClientId: config.effectiveGoogleServerClientId,
  );
});

final publicDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final dio = createPublicDio(config);
  ref.onDispose(dio.close);
  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);

  if (config.isDemoMode) {
    return DummyAuthRepository(tokenStorage: tokenStorage);
  }

  final dio = ref.watch(publicDioProvider);
  final googleClient = ref.watch(googleAuthClientProvider);
  return AuthRepositoryImpl(
    dio: dio,
    tokenStorage: tokenStorage,
    googleAuthClient: googleClient,
  );
});

final authenticatedDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  final authRepository = ref.watch(authRepositoryProvider);

  final dio = createAuthenticatedDio(
    config: config,
    interceptorBuilder: (dio) => AuthInterceptor(
      tokenStorage: tokenStorage,
      retryRequest: dio.fetch,
      onRefresh: authRepository.requestTokenRefresh,
      onTokensRefreshed: (tokens) {
        ref.read(authNotifierProvider.notifier).syncTokens(tokens);
      },
      onSessionExpired: () {
        ref.read(authNotifierProvider.notifier).expireSession();
      },
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// SSOT provider exposing parsed [JwtClaims] for the active session, or `null`.
final currentClaimsProvider = Provider<JwtClaims?>((ref) {
  return ref.watch(
    authNotifierProvider.select(
      (state) => state is AuthAuthenticated ? state.claims : null,
    ),
  );
});

/// SSOT provider exposing the active user's subject ID, or `null`.
/// Watched by user-scoped notifiers so switching accounts resets state cleanly.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentClaimsProvider.select((claims) => claims?.subject));
});

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthInitial();

  Future<void> restoreSession() async {
    state = const AuthLoading();
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.restoreSession();
    if (!ref.mounted) return;

    await result.fold<Future<void>>(
      (failure) async {
        state = AuthUnauthenticated(failure: failure);
      },
      (tokens) async {
        if (tokens == null) {
          state = const AuthUnauthenticated();
          return;
        }

        final claims = JwtClaims.tryParse(tokens.accessToken);
        if (claims != null && claims.isExpiringSoon()) {
          final refreshed = await repo.refreshTokens();
          if (!ref.mounted) return;
          state = refreshed.fold(
            (failure) => failure is UnauthorizedFailure
                ? AuthUnauthenticated(failure: failure)
                : _authenticatedState(tokens),
            _authenticatedState,
          );
          return;
        }

        state = _authenticatedState(tokens);
      },
    );
  }

  Future<bool> signInWithGoogle({String? debugAccountId}) {
    if (state is AuthLoading) return Future<bool>.value(false);
    return _authenticate(
      () => ref
          .read(authRepositoryProvider)
          .signInWithGoogle(debugAccountId: debugAccountId),
    );
  }

  Future<bool> _authenticate(
    Future<Either<AuthFailure, AuthTokens>> Function() action,
  ) async {
    state = const AuthLoading();
    final result = await action();
    if (!ref.mounted) return false;
    return result.fold<bool>(
      (failure) {
        state = AuthUnauthenticated(failure: failure);
        return false;
      },
      (tokens) {
        state = _authenticatedState(tokens);
        return true;
      },
    );
  }

  Future<void> logout() async {
    if (state is AuthLoading) return;
    state = const AuthLoading();
    final result = await ref.read(authRepositoryProvider).logout();
    if (!ref.mounted) return;
    state = result.fold(
      (failure) => AuthUnauthenticated(failure: failure),
      (_) => const AuthUnauthenticated(),
    );
  }

  /// Syncs refreshed tokens from background interceptor ONLY if the user
  /// is currently authenticated (prevents stale refresh overriding `logout()`).
  void syncTokens(AuthTokens tokens) {
    if (state is! AuthAuthenticated) return;
    state = _authenticatedState(tokens);
  }

  void expireSession() {
    state = const AuthUnauthenticated(failure: UnauthorizedFailure());
  }

  AuthAuthenticated _authenticatedState(AuthTokens tokens) {
    return AuthAuthenticated(
      tokens: tokens,
      claims: JwtClaims.tryParse(tokens.accessToken),
    );
  }
}
