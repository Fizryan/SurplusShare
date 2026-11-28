import 'package:dio/dio.dart';

/// Shared DRY utilities for parsing standard `{ "data": ... }` REST envelopes
/// and extracting backend error messages.
abstract final class ApiResponseParser {
  static Map<String, dynamic> unwrapMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Respons server tidak berformat JSON objek.');
    }
    final map = Map<String, dynamic>.from(raw);
    final inner = map['data'];
    if (inner is Map) {
      return Map<String, dynamic>.from(inner);
    }
    return map;
  }

  static Map<String, dynamic>? unwrapNullableMap(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map.containsKey('data')) {
      final inner = map['data'];
      if (inner == null) return null;
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return null;
    }
    return map;
  }

  static List<Map<String, dynamic>> unwrapList(Object? raw) {
    final Object? source = raw is Map ? raw['data'] : raw;
    if (source is! List) return const <Map<String, dynamic>>[];
    return [
      for (final item in source.whereType<Map<dynamic, dynamic>>())
        Map<String, dynamic>.from(item),
    ];
  }

  static String extractErrorMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'] ?? data['error'];
      if (msg is String && msg.trim().isNotEmpty) {
        return msg.trim();
      }
    }
    return fallback;
  }

  static String? extractErrorCode(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['code'] is String) {
      return (data['code'] as String).trim();
    }
    return null;
  }
}
