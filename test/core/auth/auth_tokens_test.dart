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
  group('AuthTokens', () {
    test('parses wrapped data with snake_case keys', () {
      final tokens = AuthTokens.fromJson(const {
        'data': {'access_token': 'access-123', 'refresh_token': 'refresh-456'},
      });

      expect(tokens.accessToken, 'access-123');
      expect(tokens.refreshToken, 'refresh-456');
    });

    test('parses wrapped data with camelCase keys', () {
      final tokens = AuthTokens.fromJson(const {
        'data': {
          'accessToken': 'access-camel',
          'refreshToken': 'refresh-camel',
        },
      });

      expect(tokens.accessToken, 'access-camel');
      expect(tokens.refreshToken, 'refresh-camel');
    });

    test('parses flat payload as fallback', () {
      final tokens = AuthTokens.fromJson(const {
        'accessToken': 'flat-access',
        'refresh_token': 'flat-refresh',
      });

      expect(tokens.accessToken, 'flat-access');
      expect(tokens.refreshToken, 'flat-refresh');
    });

    test('throws FormatException when tokens are missing or empty', () {
      expect(
        () => AuthTokens.fromJson(const {
          'data': {'access_token': ''},
        }),
        throwsFormatException,
      );
      expect(
        () => AuthTokens.fromJson(const {
          'data': {'access_token': 'ok'},
        }),
        throwsFormatException,
      );
    });

    test('redacts tokens in toString', () {
      const tokens = AuthTokens(
        accessToken: 'super-secret-access',
        refreshToken: 'super-secret-refresh',
      );

      final text = tokens.toString();
      expect(text, isNot(contains('super-secret-access')));
      expect(text, isNot(contains('super-secret-refresh')));
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
