import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// Debug-only HTTP logger that redacts Authorization headers, tokens, PINs,
/// and sensitive PII from JSON and multipart payloads.
class SanitizedLogInterceptor extends Interceptor {
  new(this._logger);

  static const _redacted = '[REDACTED]';
  static const Set<String> _sensitiveKeys = {
    'authorization',
    'password',
    'access_token',
    'refresh_token',
    'accesstoken',
    'refreshtoken',
    'session_token',
    'sessiontoken',
    'id_token',
    'idtoken',
    'google_id',
    'googleid',
    'pickup_pin',
    'pickuppin',
    'delivery_pin',
    'deliverypin',
    'contact_phone',
    'contactphone',
    'registration_number',
    'registrationnumber',
    'pin',
    'token',
    'secret',
  };

  final Logger _logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final safeHeaders = sanitize(options.headers);
    final safeBody = sanitize(options.data);
    _logger.d(
      '[HTTP -->] ${options.method} ${options.uri}\n'
      'Headers: $safeHeaders\n'
      'Body: $safeBody',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final safeBody = sanitize(response.data);
    _logger.d(
      '[HTTP <--] ${response.statusCode} ${response.requestOptions.uri}\n'
      'Body: $safeBody',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final safeBody = sanitize(err.response?.data);
    _logger.w(
      '[HTTP ERR] ${err.response?.statusCode ?? err.type.name} '
      '${err.requestOptions.uri}\n'
      'Body: $safeBody',
    );
    handler.next(err);
  }

  /// Recursively redacts sensitive keys from maps, lists, and multipart data.
  static Object? sanitize(Object? value) {
    if (value is FormData) {
      return <String, Object?>{
        'fields': <String, Object?>{
          for (final entry in value.fields)
            entry.key: _sensitiveKeys.contains(entry.key.toLowerCase())
                ? _redacted
                : entry.value,
        },
        'files': [for (final f in value.files) '${f.key}:[BINARY]'],
      };
    }
    if (value is Map) {
      return value.map<Object?, Object?>((key, val) {
        final keyStr = key?.toString().toLowerCase() ?? '';
        if (_sensitiveKeys.contains(keyStr)) {
          return MapEntry(key, _redacted);
        }
        return MapEntry(key, sanitize(val));
      });
    }
    if (value is List) {
      return value.map<Object?>(sanitize).toList(growable: false);
    }
    return value;
  }
}
