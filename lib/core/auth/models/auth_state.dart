import 'package:flutter/foundation.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/models/jwt_claims.dart';

@immutable
sealed class AuthState {
  const new();
}

final class AuthInitial extends AuthState {
  const new();

  @override
  bool operator ==(Object other) => other is AuthInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class AuthLoading extends AuthState {
  const new();

  @override
  bool operator ==(Object other) => other is AuthLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class AuthAuthenticated extends AuthState {
  const new({required this.tokens, this.claims});

  final AuthTokens tokens;
  final JwtClaims? claims;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthAuthenticated &&
        other.tokens == tokens &&
        other.claims == claims;
  }

  @override
  int get hashCode => Object.hash(tokens, claims);
}

final class AuthUnauthenticated extends AuthState {
  const new({this.failure});

  final AuthFailure? failure;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthUnauthenticated && other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(runtimeType, failure);
}
