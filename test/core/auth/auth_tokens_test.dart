import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/models/jwt_claims.dart';
import 'package:surplus_share/core/permission/app_role.dart';
import 'package:surplus_share/core/permission/permission.dart';

String _encodeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'})));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.signature';
}

void main() {
  group('AuthTokens (Single Session Token)', () {
    test('parses wrapped data with session_token and access_token keys', () {
      final session = AuthTokens.fromJson(const {
        'data': {'session_token': 'session-123'},
      });
      final access = AuthTokens.fromJson(const {
        'data': {'access_token': 'access-123'},
      });

      expect(session.accessToken, 'session-123');
      expect(access.accessToken, 'access-123');
    });

    test('parses wrapped data with camelCase and flat payload fallback', () {
      final camel = AuthTokens.fromJson(const {
        'data': {'accessToken': 'access-camel'},
      });
      final flat = AuthTokens.fromJson(const {'token': 'flat-token'});

      expect(camel.accessToken, 'access-camel');
      expect(flat.accessToken, 'flat-token');
    });

    test('throws FormatException when session token is missing or empty', () {
      expect(
        () => AuthTokens.fromJson(const {
          'data': {'access_token': ''},
        }),
        throwsFormatException,
      );
      expect(
        () => AuthTokens.fromJson(const <String, dynamic>{}),
        throwsFormatException,
      );
    });

    test('redacts token in toString', () {
      const tokens = AuthTokens(accessToken: 'super-secret-session');

      final text = tokens.toString();
      expect(text, isNot(contains('super-secret-session')));
      expect(text, contains('REDACTED'));
    });
  });

  group('JwtClaims', () {
    test('parses valid JWT claims with snake_case and camelCase', () {
      final token = _encodeJwt({
        'sub': 'user-42',
        'role': 'verified_recipient',
        'kyc_status': 'approved',
        'granted_permissions': ['browse_discount_listings'],
        'revoked_permissions': <String>[],
        'exp': 4102444800,
      });

      final claims = JwtClaims.tryParse(token);

      expect(claims, isNotNull);
      expect(claims!.subject, 'user-42');
      expect(claims.role, AppRole.verifiedRecipient);
      expect(claims.kycStatus, KycStatus.approved);
      expect(
        claims.grantedPermissions,
        equals({Permission.browseDiscountListings}),
      );
      expect(claims.isExpired, isFalse);
    });

    test('returns null for malformed JWT', () {
      expect(JwtClaims.tryParse('not-a-jwt'), isNull);
      expect(JwtClaims.tryParse('a.!!!invalid!!!.c'), isNull);
    });
  });
}
