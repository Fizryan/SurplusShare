import 'package:flutter_test/flutter_test.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/config/api_config.dart';
import 'package:surplus_share/core/network/auth_interceptor.dart';
import 'package:surplus_share/core/network/dio_extensions.dart';
import 'package:surplus_share/core/network/sanitized_log_interceptor.dart';
import 'package:surplus_share/core/theme/app_tokens.dart';
import 'package:surplus_share/core/utils/formatters/app_formatters.dart';
import 'package:surplus_share/features/location/domain/models/geo_point.dart';

void main() {
  group('SanitizedLogInterceptor.sanitize', () {
    test('redacts sensitive headers and nested payload fields', () {
      final sanitized = SanitizedLogInterceptor.sanitize({
        'Authorization': 'Bearer secret-jwt',
        'Accept': 'application/json',
        'data': {
          'email': 'user@example.com',
          'password': 'my-password',
          'access_token': 'acc-123',
          'refreshToken': 'ref-456',
          'id_token': 'google-secret-id-token',
          'pickup_pin': '123456',
          'pin': '654321',
        },
      });

      expect(sanitized, {
        'Authorization': '[REDACTED]',
        'Accept': 'application/json',
        'data': {
          'email': 'user@example.com',
          'password': '[REDACTED]',
          'access_token': '[REDACTED]',
          'refreshToken': '[REDACTED]',
          'id_token': '[REDACTED]',
          'pickup_pin': '[REDACTED]',
          'pin': '[REDACTED]',
        },
      });
    });
  });

  group('ApiConfig', () {
    test('validate throws on empty URL', () {
      const config = ApiConfig(baseUrl: '');
      expect(config.isConfigured, isFalse);
      expect(config.validate, throwsStateError);
    });

    test('validate enforces HTTPS when requireHttps is true', () {
      const httpConfig = ApiConfig(baseUrl: 'http://api.example.com');
      const httpsConfig = ApiConfig(baseUrl: 'https://api.example.com');

      expect(httpConfig.isSecure, isFalse);
      expect(() => httpConfig.validate(requireHttps: true), throwsStateError);
      expect(httpConfig.validate, returnsNormally);

      expect(httpsConfig.isSecure, isTrue);
      expect(() => httpsConfig.validate(requireHttps: true), returnsNormally);
    });
  });

  group('AppFormatters & GeoPoint edge cases', () {
    test('formats Rupiah cleanly', () {
      expect(AppFormatters.formatRupiah(25000), contains('25.000'));
    });

    test('GeoPoint.distanceInKmTo handles antipodal points without NaN', () {
      const north = GeoPoint(latitude: 0, longitude: 0);
      const south = GeoPoint(latitude: 0, longitude: 180);
      final distance = north.distanceInKmTo(south);
      expect(distance.isNaN, isFalse);
      expect(distance, greaterThan(20000));
    });
  });

  group('AppBreakpoints', () {
    test('returns proportional padding and width per screen size', () {
      expect(AppBreakpoints.horizontalPadding(320), AppSpacing.lg);
      expect(AppBreakpoints.horizontalPadding(393), AppSpacing.xxl);
      expect(AppBreakpoints.horizontalPadding(840), AppSpacing.xxxl);

      expect(AppBreakpoints.cardPadding(320), AppSpacing.lg);
      expect(AppBreakpoints.cardPadding(393), AppSpacing.xl);
      expect(AppBreakpoints.cardPadding(840), AppSpacing.xxl);

      expect(AppBreakpoints.authMaxWidth(393), 400);
      expect(AppBreakpoints.authMaxWidth(840), 440);
    });
  });

  group('AuthRequestOptions & AuthFailure.isRetryable', () {
    test('AuthRequestOptions.public sets skip_auth extra flag', () {
      final options = AuthRequestOptions.public(headers: {'X-Test': '1'});
      expect(options.extra?[AuthInterceptor.skipAuthKey], isTrue);
      expect(options.headers?['X-Test'], '1');
    });

    test('AuthFailure.isRetryable marks network and 5xx as retryable', () {
      expect(const NetworkFailure().isRetryable, isTrue);
      expect(const ServerFailure('down', statusCode: 503).isRetryable, isTrue);
      expect(const ServerFailure('bad', statusCode: 400).isRetryable, isFalse);
      expect(const UnauthorizedFailure().isRetryable, isFalse);
      expect(const StorageFailure().isRetryable, isFalse);
      expect(const AuthCancelledFailure().isRetryable, isFalse);
    });
  });
}
